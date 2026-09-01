// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20, IFeed, ISwapRouter} from "./AUM0.sol";

/// AUM Zero, wallet edition. The asset manager that never holds your money.
///
/// There is no deposit. Your stocks and your cash sit in your own wallet, where
/// your wallet app can see them, and they stay there. You grant an allowance and
/// carve a target allocation; from then on strangers may rebalance you, and each
/// rebalance pulls from your wallet, swaps, and hands the result straight back
/// to your wallet inside the same transaction. This contract's balance is zero
/// before the trade and zero after it.
///
/// Why an allowance is safe here:
///
///   1. Every rebalance must move the wallet strictly CLOSER to your own
///      target, measured before and after on your real balances. No
///      improvement, no trade.
///   2. Every fill is checked against the chain's official feeds, on the
///      amount your wallet actually received, not the amount promised.
///   3. There is no function anywhere in this contract that names a
///      destination. Swap output goes to the owner. The bounty, sized by you,
///      goes to whoever did the work. Nothing else can move.
///
/// You quit by setting the allowance to zero. Nothing to withdraw: you never
/// gave anything up.
///
/// The asset list, feeds, and venue are fixed at construction. No owner, no
/// admin, no upgrade path.
contract AUM0Wallet {
    struct Asset {
        address token;
        address feed;     // 1e8 USD feed; address(0) means the quote itself ($1)
        uint24 poolFee;   // fee tier of the token/quote pool
        uint8 decimals;
    }

    ISwapRouter public immutable router;
    IERC20 public immutable quote;
    uint8 public immutable quoteDecimals;
    uint256 public immutable maxPriceAge;

    Asset[] private _assets;   // index 0 is always the quote

    struct Account {
        uint16[] targetBps;
        uint16 minDriftBps;
        uint16 bandBps;
        uint128 bountyQuote;
    }

    mapping(address => Account) private _accounts;

    event TargetSet(address indexed user, uint16[] targetBps, uint16 minDriftBps, uint16 bandBps, uint128 bountyQuote);
    event Rebalanced(address indexed user, address indexed keeper, uint256 driftBefore, uint256 driftAfter, uint256 bounty);

    error BadAsset();
    error BadWeights();
    error BadParams();
    error NotConfigured();
    error StaleFeed(uint256 asset);
    error BadPrice(int256 answer);
    error DriftBelowThreshold(uint256 drift, uint256 threshold);
    error DriftNotImproved(uint256 before_, uint256 after_);
    error FillOutsideBand(uint256 inUsd, uint256 outUsd, uint16 bandBps);
    error TransferFailed();

    constructor(
        address _router,
        address _quote,
        uint8 _quoteDecimals,
        uint256 _maxPriceAge,
        address[] memory tokens,
        address[] memory feeds,
        uint24[] memory poolFees,
        uint8[] memory tokenDecimals
    ) {
        router = ISwapRouter(_router);
        quote = IERC20(_quote);
        quoteDecimals = _quoteDecimals;
        maxPriceAge = _maxPriceAge;

        _assets.push(Asset({token: _quote, feed: address(0), poolFee: 0, decimals: _quoteDecimals}));
        for (uint256 i; i < tokens.length; ++i) {
            _assets.push(Asset({token: tokens[i], feed: feeds[i], poolFee: poolFees[i], decimals: tokenDecimals[i]}));
            IERC20(tokens[i]).approve(_router, type(uint256).max);
        }
        IERC20(_quote).approve(_router, type(uint256).max);
    }

    /// Carve your policy. targetBps runs over all assets (quote first) and must
    /// sum to 10000. It applies to whatever the venue's assets are worth in your
    /// wallet, so cash you do not want managed belongs in a different wallet.
    function setTarget(uint16[] calldata targetBps, uint16 minDriftBps, uint16 bandBps, uint128 bountyQuote) external {
        if (targetBps.length != _assets.length) revert BadWeights();
        uint256 s;
        for (uint256 i; i < targetBps.length; ++i) s += targetBps[i];
        if (s != 10000) revert BadWeights();
        if (bandBps == 0 || bandBps > 1000 || minDriftBps == 0) revert BadParams();
        _accounts[msg.sender] = Account({
            targetBps: targetBps,
            minDriftBps: minDriftBps,
            bandBps: bandBps,
            bountyQuote: bountyQuote
        });
        emit TargetSet(msg.sender, targetBps, minDriftBps, bandBps, bountyQuote);
    }

    struct Trade {
        uint256 sellAsset;  // one side must be the quote (index 0)
        uint256 buyAsset;
        uint256 amountIn;   // raw units of sellAsset
    }

    /// Anyone may call this on any configured wallet. Nothing is held: each leg
    /// pulls from the owner, swaps, and delivers to the owner. The wallet must
    /// end strictly closer to its target than it began, or all of it reverts.
    function rebalance(address user, Trade[] calldata trades) external {
        Account storage acct = _accounts[user];
        if (acct.targetBps.length == 0) revert NotConfigured();

        uint256[] memory prices = _priceAll();
        uint256 driftBefore = _drift(user, prices);
        if (driftBefore < acct.minDriftBps) revert DriftBelowThreshold(driftBefore, acct.minDriftBps);

        for (uint256 i; i < trades.length; ++i) {
            _execute(user, trades[i], prices, acct.bandBps);
        }

        uint256 driftAfter = _drift(user, prices);
        if (driftAfter >= driftBefore) revert DriftNotImproved(driftBefore, driftAfter);

        // Proportional to the help given, so splitting one rebalance into many
        // pays exactly the same total: the payouts telescope.
        uint256 bounty = (uint256(acct.bountyQuote) * (driftBefore - driftAfter)) / 10000;
        if (bounty > 0) {
            if (!quote.transferFrom(user, msg.sender, bounty)) revert TransferFailed();
        }
        emit Rebalanced(user, msg.sender, driftBefore, driftAfter, bounty);
    }

    function _execute(address user, Trade calldata t, uint256[] memory prices, uint16 bandBps) internal {
        if (t.sellAsset != 0 && t.buyAsset != 0) revert BadAsset();   // every leg touches cash
        if (t.sellAsset == t.buyAsset) revert BadAsset();
        if (t.sellAsset >= _assets.length || t.buyAsset >= _assets.length) revert BadAsset();

        Asset memory sellA = _assets[t.sellAsset];
        Asset memory buyA = _assets[t.buyAsset];

        if (!IERC20(sellA.token).transferFrom(user, address(this), t.amountIn)) revert TransferFailed();

        uint256 heldBefore = IERC20(buyA.token).balanceOf(user);
        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: sellA.token,
                tokenOut: buyA.token,
                fee: t.sellAsset == 0 ? buyA.poolFee : sellA.poolFee,
                recipient: user,          // the owner is the only destination
                amountIn: t.amountIn,
                amountOutMinimum: 0,      // the band check below is the real guard
                sqrtPriceLimitX96: 0
            })
        );
        uint256 out = IERC20(buyA.token).balanceOf(user) - heldBefore;

        // Wall two, on what the wallet actually received.
        uint256 inUsd = _usd(t.sellAsset, t.amountIn, prices);
        uint256 outUsd = _usd(t.buyAsset, out, prices);
        if (outUsd < (inUsd * (10000 - bandBps)) / 10000) revert FillOutsideBand(inUsd, outUsd, bandBps);
    }

    // -- valuation, read straight off the wallet -------------------------------

    function _priceAll() internal view returns (uint256[] memory prices) {
        uint256 n = _assets.length;
        prices = new uint256[](n);
        prices[0] = 1e8;
        for (uint256 i = 1; i < n; ++i) {
            (, int256 p, , uint256 updatedAt, ) = IFeed(_assets[i].feed).latestRoundData();
            if (p <= 0) revert BadPrice(p);
            if (block.timestamp - updatedAt > maxPriceAge) revert StaleFeed(i);
            prices[i] = uint256(p);
        }
    }

    function _usd(uint256 asset, uint256 amount, uint256[] memory prices) internal view returns (uint256) {
        return (amount * prices[asset] * 1e10) / (10 ** _assets[asset].decimals);
    }

    function _drift(address user, uint256[] memory prices) internal view returns (uint256 d) {
        Account storage acct = _accounts[user];
        if (acct.targetBps.length == 0) return 0;   // no law, no distance from it
        uint256 n = _assets.length;
        uint256 total;
        uint256[] memory usd = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            usd[i] = _usd(i, IERC20(_assets[i].token).balanceOf(user), prices);
            total += usd[i];
        }
        if (total == 0) return 0;
        for (uint256 i; i < n; ++i) {
            uint256 w = (usd[i] * 10000) / total;
            uint256 t = acct.targetBps[i];
            d += w > t ? w - t : t - w;
        }
    }

    // -- views -----------------------------------------------------------------

    function drift(address user) external view returns (uint256) {
        return _drift(user, _priceAll());
    }

    function valueOf(address user) external view returns (uint256 totalUsd) {
        uint256[] memory prices = _priceAll();
        for (uint256 i; i < _assets.length; ++i) {
            totalUsd += _usd(i, IERC20(_assets[i].token).balanceOf(user), prices);
        }
    }

    function heldBy(address user, uint256 asset) external view returns (uint256) {
        return IERC20(_assets[asset].token).balanceOf(user);
    }

    function accountOf(address user)
        external
        view
        returns (uint16[] memory targetBps, uint16 minDriftBps, uint16 bandBps, uint128 bountyQuote)
    {
        Account storage a = _accounts[user];
        return (a.targetBps, a.minDriftBps, a.bandBps, a.bountyQuote);
    }

    function assetCount() external view returns (uint256) {
        return _assets.length;
    }

    function assetAt(uint256 i) external view returns (address token, address feed, uint24 poolFee, uint8 decimals) {
        Asset memory a = _assets[i];
        return (a.token, a.feed, a.poolFee, a.decimals);
    }
}
