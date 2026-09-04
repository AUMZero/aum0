// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20, IFeed, ISwapRouter} from "./AUM0.sol";

/// AUM Zero, shelf edition. Anyone can manufacture a fund. No one can charge for it.
///
/// A law is a target allocation: so much of each stock, so much cash. Carving
/// one costs a transaction. Once carved it is immutable, owned by no one, and
/// sits on the shelf forever. A law's id is the hash of its numbers, so the
/// same allocation is the same fund no matter who carves it or when.
///
/// A wallet joins a fund by adopting its law. There is no deposit and no fund
/// token: your stocks and your cash stay in your own wallet, and strangers
/// keep you on the law you chose, paid only the bounty you yourself offered.
/// The carver of a law earns nothing. The contract earns nothing. There is no
/// function in this file that could collect a fee, because a fee would need
/// somewhere to go, and no destination exists.
///
///   1. Every rebalance must move the wallet strictly CLOSER to its adopted
///      law, measured before and after on real balances. No improvement, no
///      trade.
///   2. Every fill is checked against the chain's official feeds, on the
///      amount the wallet actually received, not the amount promised.
///   3. Swap output goes to the owner. The bounty goes to whoever did the
///      work. Nothing else can move.
///
/// You quit by setting the allowance to zero. Nothing to withdraw: you never
/// gave anything up.
///
/// The asset list, feeds, and venue are fixed at construction. No owner, no
/// admin, no upgrade path.
contract AUM0Shelf {
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

    // The shelf. A law's id is the hash of its allocation, so laws are
    // content-addressed: no counter, no registry, no duplicates.
    mapping(bytes32 => uint16[]) private _laws;

    struct Account {
        bytes32 lawId;
        uint16 minDriftBps;
        uint16 bandBps;
        uint128 bountyQuote;
    }

    mapping(address => Account) private _accounts;

    event LawCarved(bytes32 indexed lawId, uint16[] targetBps, address indexed carver);
    event Adopted(address indexed user, bytes32 indexed lawId, uint16 minDriftBps, uint16 bandBps, uint128 bountyQuote);
    event Rebalanced(address indexed user, address indexed keeper, uint256 driftBefore, uint256 driftAfter, uint256 bounty);

    error BadAsset();
    error BadWeights();
    error BadParams();
    error NoSuchLaw();
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

    // -- the shelf -------------------------------------------------------------

    /// Manufacture a fund. targetBps runs over all assets (quote first) and
    /// must sum to 10000. Carving the same allocation twice returns the same
    /// law and changes nothing: the shelf holds each fund exactly once.
    function carveLaw(uint16[] calldata targetBps) external returns (bytes32 lawId) {
        if (targetBps.length != _assets.length) revert BadWeights();
        uint256 s;
        for (uint256 i; i < targetBps.length; ++i) s += targetBps[i];
        if (s != 10000) revert BadWeights();

        lawId = keccak256(abi.encode(targetBps));
        if (_laws[lawId].length == 0) {
            _laws[lawId] = targetBps;
            emit LawCarved(lawId, targetBps, msg.sender);
        }
    }

    /// Put your wallet under a law. The guardrails are yours, not the law's:
    /// how far you may drift, how bad a fill you will accept, what a full
    /// journey back to target is worth to you.
    function adopt(bytes32 lawId, uint16 minDriftBps, uint16 bandBps, uint128 bountyQuote) external {
        if (_laws[lawId].length == 0) revert NoSuchLaw();
        if (bandBps == 0 || bandBps > 1000 || minDriftBps == 0) revert BadParams();
        _accounts[msg.sender] = Account({
            lawId: lawId,
            minDriftBps: minDriftBps,
            bandBps: bandBps,
            bountyQuote: bountyQuote
        });
        emit Adopted(msg.sender, lawId, minDriftBps, bandBps, bountyQuote);
    }

    struct Trade {
        uint256 sellAsset;  // one side must be the quote (index 0)
        uint256 buyAsset;
        uint256 amountIn;   // raw units of sellAsset
    }

    /// Anyone may call this on any wallet that adopted a law. Nothing is held:
    /// each leg pulls from the owner, swaps, and delivers to the owner. The
    /// wallet must end strictly closer to its law than it began, or all of it
    /// reverts.
    function rebalance(address user, Trade[] calldata trades) external {
        Account storage acct = _accounts[user];
        if (acct.lawId == bytes32(0)) revert NotConfigured();

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
        if (acct.lawId == bytes32(0)) return 0;   // no law, no distance from it
        uint16[] storage law = _laws[acct.lawId];
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
            uint256 t = law[i];
            d += w > t ? w - t : t - w;
        }
    }

    // -- views -----------------------------------------------------------------

    function lawOf(bytes32 lawId) external view returns (uint16[] memory) {
        return _laws[lawId];
    }

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
        returns (bytes32 lawId, uint16 minDriftBps, uint16 bandBps, uint128 bountyQuote)
    {
        Account storage a = _accounts[user];
        return (a.lawId, a.minDriftBps, a.bandBps, a.bountyQuote);
    }

    function assetCount() external view returns (uint256) {
        return _assets.length;
    }

    function assetAt(uint256 i) external view returns (address token, address feed, uint24 poolFee, uint8 decimals) {
        Asset memory a = _assets[i];
        return (a.token, a.feed, a.poolFee, a.decimals);
    }
}
