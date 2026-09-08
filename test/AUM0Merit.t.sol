// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0Merit} from "../src/AUM0Merit.sol";
import {StrictERC20, MockFeed, MockRouter} from "./AUM0Wallet.t.sol";

/// The claim under test: a manager is paid only for being right, and cannot
/// break a promise they carved themselves. The number that decides both is the
/// official feed, which nobody here can restate.
contract AUM0MeritTest is Test {
    AUM0Merit aum;
    StrictERC20 usdg;
    StrictERC20 nvda;
    MockFeed nvdaFeed;
    MockRouter router;

    address author = address(0xA07704);
    address f1 = address(0xF001);
    address f2 = address(0xF002);
    address worker = address(0xC0FFEE);

    function setUp() public {
        usdg = new StrictERC20("USDG", 6);
        nvda = new StrictERC20("NVDA", 18);
        nvdaFeed = new MockFeed(200e8);
        router = new MockRouter(usdg);
        router.register(nvda, nvdaFeed);

        address[] memory tokens = new address[](1);
        tokens[0] = address(nvda);
        address[] memory feeds = new address[](1);
        feeds[0] = address(nvdaFeed);
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;
        uint8[] memory decs = new uint8[](1);
        decs[0] = 18;
        aum = new AUM0Merit(address(router), address(usdg), 6, 7 days, tokens, feeds, fees, decs);

        usdg.mint(f1, 20000e6);
        usdg.mint(f2, 20000e6);
        for (uint256 i; i < 2; ++i) {
            address who = i == 0 ? f1 : f2;
            vm.startPrank(who);
            usdg.approve(address(aum), type(uint256).max);
            nvda.approve(address(aum), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _pair(uint16 a, uint16 b) internal pure returns (uint16[] memory t) {
        t = new uint16[](2);
        t[0] = a; t[1] = b;
    }

    function _none() internal pure returns (uint16[] memory t) {
        t = new uint16[](0);
    }

    /// half cash half stock, a tenth of any bounty, no covenant
    function _publish(uint16 royalty) internal returns (uint256 id) {
        vm.prank(author);
        id = aum.publish(_pair(5000, 5000), _none(), 0, 0, royalty, 0, 0);
    }

    /// What a worker would actually do: size the one leg that closes the gap
    /// between what the wallet holds and what its law asks for, either way.
    function _serveAt(address who, uint256 px) internal {
        (uint16[] memory t,,,) = aum.accountOf(who);
        uint256 cash = usdg.balanceOf(who);
        uint256 stock = (nvda.balanceOf(who) * px) / 1e20;
        uint256 want = ((cash + stock) * t[1]) / 10000;
        AUM0Merit.Trade[] memory tr = new AUM0Merit.Trade[](1);
        if (want > stock) {
            tr[0] = AUM0Merit.Trade({sellAsset: 0, buyAsset: 1, amountIn: ((want - stock) * 97) / 100, fill: AUM0Merit.Fill.POOL, amountOut: 0});
        } else {
            tr[0] = AUM0Merit.Trade({sellAsset: 1, buyAsset: 0, amountIn: (((stock - want) * 97) / 100) * 1e20 / px, fill: AUM0Merit.Fill.POOL, amountOut: 0});
        }
        vm.prank(worker);
        aum.rebalance(who, tr);
    }

    /// The headline. The market falls, the follower is still served, the worker
    /// is still paid, and the manager gets nothing, because the manager was
    /// wrong. On Wall Street the fee arrives either way.
    function test_aManagerWhoIsWrongIsPaidNothing() public {
        uint256 id = _publish(1000);
        vm.prank(f1);
        aum.follow(id, 100, 200, 100e6);

        nvdaFeed.set(150e8);           // the allocation loses a quarter
        _serveAt(f1, 150e8);

        assertEq(usdg.balanceOf(author), 0, "a manager who is down collects nothing");
        assertGt(usdg.balanceOf(worker), 0, "the worker is still paid in full for real work");
    }

    /// And when the same manager is right, the royalty arrives.
    function test_aManagerWhoIsRightIsPaid() public {
        uint256 id = _publish(1000);
        vm.prank(f1);
        aum.follow(id, 100, 200, 100e6);

        nvdaFeed.set(260e8);           // the allocation gains
        _serveAt(f1, 260e8);

        emit log_named_decimal_uint("author royalty", usdg.balanceOf(author), 6);
        assertGt(usdg.balanceOf(author), 0, "being right is the whole job");
    }

    /// The high water mark cannot be walked back. Down, then up but not all the
    /// way up, is still down: nothing is owed until the old peak is beaten.
    function test_theMarkCannotBeWalkedBack() public {
        uint256 id = _publish(1000);
        vm.prank(f1);
        aum.follow(id, 100, 200, 100e6);

        _serveAt(f1, 200e8);           // on the law to begin with

        nvdaFeed.set(300e8);           // a peak, and it is collected on
        _serveAt(f1, 300e8);
        uint256 afterPeak = usdg.balanceOf(author);
        assertGt(afterPeak, 0, "paid at the peak");

        nvdaFeed.set(150e8);           // a fall
        _serveAt(f1, 150e8);
        assertEq(usdg.balanceOf(author), afterPeak, "nothing owed on the way down");

        // A partial recovery. The record is the blended allocation, not one
        // stock, so the bar is where the whole policy stood, not where the
        // stock did.
        nvdaFeed.set(240e8);
        _serveAt(f1, 240e8);
        assertEq(usdg.balanceOf(author), afterPeak, "and nothing owed until the peak is beaten");

        nvdaFeed.set(600e8);           // a new high at last
        _serveAt(f1, 600e8);
        assertGt(usdg.balanceOf(author), afterPeak, "a new high pays again");
    }

    /// Every follower brings their own mark. Somebody who signs after a rise
    /// never pays the manager for the part they were not there for. Wall Street
    /// pools everybody into one number and cannot do this.
    function test_youNeverPayForARiseYouMissed() public {
        uint256 id = _publish(1000);
        vm.prank(f1);
        aum.follow(id, 100, 200, 100e6);

        nvdaFeed.set(400e8);           // the whole rise happens before f2 arrives
        vm.prank(f2);
        aum.follow(id, 100, 200, 100e6);

        _serveAt(f2, 400e8);
        assertEq(usdg.balanceOf(author), 0, "the newcomer owes nothing for a rise they missed");

        _serveAt(f1, 400e8);
        assertGt(usdg.balanceOf(author), 0, "while the one who was there through it pays");
    }

    /// The covenant. An author writes their own limit into the policy and then
    /// cannot cross it, not later, not ever, not even to save themselves.
    function test_theAuthorCannotBreakTheirOwnPromise() public {
        vm.prank(author);
        uint256 id = aum.publish(_pair(5000, 5000), _none(), 0, 0, 1000, 6000, 1000);

        vm.prank(author);
        vm.expectRevert(AUM0Merit.CovenantBroken.selector);
        aum.revise(id, _pair(0, 10000), _none(), 0, 0);       // everything into one name

        vm.prank(author);
        vm.expectRevert(AUM0Merit.CovenantBroken.selector);
        aum.revise(id, _pair(500, 9500), _none(), 0, 0);      // and the cash floor holds too

        vm.prank(author);
        aum.revise(id, _pair(4000, 6000), _none(), 0, 0);     // inside the promise, allowed
        (uint16 maxAsset, uint16 minCash,) = aum.covenantOf(id);
        assertEq(maxAsset, 6000);
        assertEq(minCash, 1000);
    }

    /// A promise cannot be published that the policy itself already breaks.
    function test_aPolicyCannotBePublishedOutsideItsOwnPromise() public {
        vm.prank(author);
        vm.expectRevert(AUM0Merit.CovenantBroken.selector);
        aum.publish(_pair(2000, 8000), _none(), 0, 0, 1000, 5000, 0);
    }

    /// The record is the feeds and nothing else, and a revision cannot rewrite
    /// what already happened: the index is brought current under the old
    /// weights before the new ones take effect.
    function test_aRevisionCannotRewriteThePast() public {
        uint256 id = _publish(1000);
        vm.prank(f1);
        aum.follow(id, 100, 200, 100e6);

        _serveAt(f1, 200e8);                     // actually holding the allocation

        nvdaFeed.set(100e8);                     // the allocation halves its stock leg
        vm.prank(author);
        aum.revise(id, _pair(10000, 0), _none(), 0, 0);   // flee to cash after the fact

        (,, uint256 idx) = aum.covenantOf(id);
        assertLt(idx, 1e18, "the loss stayed on the record");

        nvdaFeed.set(500e8);                     // stock rips, but the policy is all cash now
        _serveAt(f1, 500e8);
        assertEq(usdg.balanceOf(author), 0, "and cash earns the author nothing");
    }

    /// Nothing above changed the walls. Money still lands in three places only.
    function test_theWallsAreUntouched() public {
        uint256 id = _publish(1000);
        vm.prank(f1);
        aum.follow(id, 100, 200, 100e6);
        nvdaFeed.set(260e8);
        _serveAt(f1, 260e8);
        assertEq(usdg.balanceOf(address(aum)), 0, "the manager held no cash");
        assertEq(nvda.balanceOf(address(aum)), 0, "and no stock");
        assertLt(aum.drift(f1), 1500, "and the follower was actually served");
    }
}
