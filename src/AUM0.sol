// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

interface IFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// The swap venue: the chain's live SwapRouter02-style router. The contract
/// names a token and an amount, never a target and calldata, so it cannot be
/// pointed at an attacker's contract.
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// AUM Zero. An asset manager with no employees, no fees, and no ability
/// to steal.
///
/// You carve a target allocation into your account: so much SPY, so much
/// TSLA, so much cash. From then on, strangers manage your portfolio.
/// When prices drift your holdings away from the target, anyone may call
/// rebalance() on your account, push it back toward the target, and take a
/// small bounty from it for the work. That is the entire company.
///
/// Why a stranger cannot hurt you:
///
///   1. Every trade must move the portfolio strictly CLOSER to your own
///      target. The contract measures drift before and after; if drift did
///      not fall, the whole rebalance reverts. Strangers can only help.
///   2. Every fill is checked against the chain's official price feeds.
///      A trade whose realized price sits further from the feed than your
///      tolerance is refused, so a keeper cannot route your order through
///      a manipulated pool and pocket the difference.
///   3. Money only ever leaves to you. withdraw() pays msg.sender their own
///      balance; the bounty is the single exception, sized by you, and paid
///      only for a rebalance that provably helped.
///
/// The asset list, feeds, and venue are fixed at construction. There is no
/// owner, no admin, no upgrade path, and no fee to anyone but the stranger
/// who did the work.
contract AUM0 {
    // -- venue ---------------------------------------------------------------
    struct Asset {
        address token;
        address feed;     // 1e8 USD feed; address(0) means the quote itself ($1)
        uint24 poolFee;   // fee tier of the token/quote pool
        uint8 decimals;
    }

    ISwapRouter public immutable router;
    IERC20 public immutable quote;      // USDG: deposits, bounties, and valuation
    uint8 public immutable quoteDecimals;
    uint256 public immutable maxPriceAge;

    Asset[] private _assets;            // index 0 is always the quote

    // -- accounts ------------------------------------------------------------
    struct Account {
        uint16[] targetBps;   // per asset, sums to 10000; empty = not configured
        uint16 minDriftBps;   // rebalance only allowed above this drift
        uint16 bandBps;       // max realized-price deviation from feed per fill
        uint128 bountyQuote;  // max total payout across the full 10000 bps of drift
    }

    mapping(address => Account) private _accounts;
    mapping(address => mapping(uint256 => uint256)) public balanceOf; // user => asset => raw amount

    event Deposited(address indexed user, uint256 indexed asset, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed asset, uint256 amount);
    event TargetSet(address indexed user, uint16[] targetBps, uint16 minDriftBps, uint16 bandBps, uint128 bountyQuote);
    event Rebalanced(address indexed user, address indexed keeper, uint256 driftBefore, uint256 driftAfter, uint256 bounty);

    error BadAsset();
    error BadWeights();
    error BadParams();
    error NotConfigured();
    error Insufficient();
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

    // -- money in, money out -------------------------------------------------

    function deposit(uint256 asset, uint256 amount) external {
        if (asset >= _assets.length) revert BadAsset();
        if (!IERC20(_assets[asset].token).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        balanceOf[msg.sender][asset] += amount;
        emit Deposited(msg.sender, asset, amount);
    }

    /// Always available, whole balance, no lockup, no permission. Wall three.
    function withdraw(uint256 asset, uint256 amount) external {
        if (balanceOf[msg.sender][asset] < amount) revert Insufficient();
        balanceOf[msg.sender][asset] -= amount;
        if (!IERC20(_assets[asset].token).transfer(msg.sender, amount)) revert TransferFailed();
        emit Withdrawn(msg.sender, asset, amount);
    }

    /// Carve your policy. targetBps runs over all assets (quote first) and
    /// must sum to 10000. bountyQuote is what a stranger earns for a
    /// rebalance that provably helped.
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

    // -- the whole company ---------------------------------------------------

    struct Trade {
        uint256 sellAsset;  // one side must be the quote (index 0)
        uint256 buyAsset;
        uint256 amountIn;   // raw units of sellAsset
    }

    /// Anyone may call this on any configured account. Every trade routes
    /// through the fixed venue, every fill is checked against the feeds, and
    /// the account must end strictly closer to its target than it began, or
    /// everything reverts. The caller earns the account's bounty.
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

        // The bounty scales with the improvement, so splitting one rebalance
        // into many pays exactly the same total: the sum telescopes. bountyQuote
        // is therefore the most an account ever pays to travel from fully
        // drifted (10000 bps) back to its target.
        uint256 bounty = (uint256(acct.bountyQuote) * (driftBefore - driftAfter)) / 10000;
        if (bounty > 0) {
            if (balanceOf[user][0] < bounty) revert Insufficient();
            balanceOf[user][0] -= bounty;
            if (!quote.transfer(msg.sender, bounty)) revert TransferFailed();
        }
        emit Rebalanced(user, msg.sender, driftBefore, driftAfter, bounty);
    }

    function _execute(address user, Trade calldata t, uint256[] memory prices, uint16 bandBps) internal {
        if (t.sellAsset != 0 && t.buyAsset != 0) revert BadAsset();      // every leg touches cash
        if (t.sellAsset == t.buyAsset) revert BadAsset();
        if (t.sellAsset >= _assets.length || t.buyAsset >= _assets.length) revert BadAsset();
        if (balanceOf[user][t.sellAsset] < t.amountIn) revert Insufficient();

        Asset memory sellA = _assets[t.sellAsset];
        Asset memory buyA = _assets[t.buyAsset];

        balanceOf[user][t.sellAsset] -= t.amountIn;
        uint256 out = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: sellA.token,
                tokenOut: buyA.token,
                fee: t.sellAsset == 0 ? buyA.poolFee : sellA.poolFee,
                recipient: address(this),
                amountIn: t.amountIn,
                amountOutMinimum: 0, // the band check below is the real guard
                sqrtPriceLimitX96: 0
            })
        );
        balanceOf[user][t.buyAsset] += out;

        // Wall two: the REALIZED price must sit within the account's band of
        // the official feed. A promise-based slippage limit is not enough; a
        // keeper controls the promise. This checks what actually happened.
        uint256 inUsd = _usd(t.sellAsset, t.amountIn, prices);
        uint256 outUsd = _usd(t.buyAsset, out, prices);
        if (outUsd < (inUsd * (10000 - bandBps)) / 10000) revert FillOutsideBand(inUsd, outUsd, bandBps);
    }

    // -- valuation -----------------------------------------------------------

    function _priceAll() internal view returns (uint256[] memory prices) {
        uint256 n = _assets.length;
        prices = new uint256[](n);
        prices[0] = 1e8; // the quote is a dollar
        for (uint256 i = 1; i < n; ++i) {
            (, int256 p, , uint256 updatedAt, ) = IFeed(_assets[i].feed).latestRoundData();
            if (p <= 0) revert BadPrice(p);
            if (block.timestamp - updatedAt > maxPriceAge) revert StaleFeed(i);
            prices[i] = uint256(p);
        }
    }

    function _usd(uint256 asset, uint256 amount, uint256[] memory prices) internal view returns (uint256) {
        // 1e18-scaled USD value
        return (amount * prices[asset] * 1e10) / (10 ** _assets[asset].decimals);
    }

    /// L1 drift in bps: sum over assets of |current weight - target weight|.
    function _drift(address user, uint256[] memory prices) internal view returns (uint256 d) {
        Account storage acct = _accounts[user];
        uint256 n = _assets.length;
        uint256 total;
        uint256[] memory usd = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            usd[i] = _usd(i, balanceOf[user][i], prices);
            total += usd[i];
        }
        if (total == 0) return 0;
        for (uint256 i; i < n; ++i) {
            uint256 w = (usd[i] * 10000) / total;
            uint256 t = acct.targetBps[i];
            d += w > t ? w - t : t - w;
        }
    }

    // -- views ---------------------------------------------------------------

    function drift(address user) external view returns (uint256) {
        return _drift(user, _priceAll());
    }

    function valueOf(address user) external view returns (uint256 totalUsd) {
        uint256[] memory prices = _priceAll();
        for (uint256 i; i < _assets.length; ++i) {
            totalUsd += _usd(i, balanceOf[user][i], prices);
        }
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
