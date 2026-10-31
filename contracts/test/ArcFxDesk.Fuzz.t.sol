// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ArcFxDeskTestBase} from "./ArcFxDesk.Base.t.sol";
import {ArcFxDesk} from "../ArcFxDesk.sol";

contract ArcFxDeskFuzzTest is ArcFxDeskTestBase {
    function _configure(uint256 rate_, uint256 bps) internal {
        vm.startPrank(owner);
        desk.setRate(rate_);
        desk.setFeeBps(uint16(bps));
        desk.setMaxAmountPerSwap(type(uint64).max);
        vm.stopPrank();
        eurc.mint(address(desk), 1e40); // ample inventory
        usdc.mint(alice, 1e30);
    }

    function testFuzz_QuoteArithmetic(uint256 amountIn, uint256 rate_, uint256 bps) public {
        amountIn = bound(amountIn, 1, type(uint64).max);
        rate_ = bound(rate_, 1, 1e24);
        bps = bound(bps, 0, 1000);
        _configure(rate_, bps);

        uint256 gross = (amountIn * rate_) / 1e18;
        uint256 fee = (gross * bps) / 10_000;
        uint256 net = gross - fee;

        if (net == 0) {
            vm.prank(alice);
            vm.expectRevert(ArcFxDesk.ZeroOutput.selector);
            desk.requestQuote(amountIn);
            return;
        }

        uint256 id = _quote(alice, amountIn);
        ArcFxDesk.Quote memory q = desk.getQuote(id);
        assertEq(q.estimatedOut, gross, "gross");
        assertEq(q.fee, fee, "fee");
        assertEq(q.minReceived, net, "net");
        assertEq(q.estimatedOut, q.fee + q.minReceived, "net = gross - fee");
        assertLe(q.fee, q.estimatedOut / 10 + 1, "fee <= 10% gross");
        assertEq(q.rate, rate_);
        assertEq(q.expiry, block.timestamp + 60);
    }

    function testFuzz_ExecutePaysLockedNetAndKeepsFee(uint256 amountIn, uint256 rate_, uint256 bps) public {
        amountIn = bound(amountIn, 1, type(uint64).max);
        rate_ = bound(rate_, 1e12, 1e24);
        bps = bound(bps, 0, 1000);
        _configure(rate_, bps);

        uint256 net = _net(amountIn, rate_, bps);
        if (net == 0) return;
        uint256 id = _quote(alice, amountIn);

        uint256 deskEurcBefore = eurc.balanceOf(address(desk));
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        _exec(alice, id, net);

        assertEq(eurc.balanceOf(alice), net);
        assertEq(eurc.balanceOf(address(desk)), deskEurcBefore - net);
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore - amountIn);
        assertEq(usdc.balanceOf(address(desk)), amountIn);
    }

    function testFuzz_RateChangeDoesNotAffectLockedQuote(uint256 amountIn, uint256 newRate, uint256 newBps) public {
        amountIn = bound(amountIn, 1e6, 5e6);
        newRate = bound(newRate, 1, 1e24);
        newBps = bound(newBps, 0, 1000);
        uint256 id = _quote(alice, amountIn);
        uint256 expected = _net(amountIn, RATE, FEE_BPS);

        vm.startPrank(owner);
        desk.setRate(newRate);
        desk.setFeeBps(uint16(newBps));
        vm.stopPrank();

        assertEq(desk.getQuote(id).minReceived, expected);
        _exec(alice, id, expected);
        assertEq(eurc.balanceOf(alice), expected);
    }

    function testFuzz_ExpiryBoundary(uint256 dt) public {
        dt = bound(dt, 0, 1000);
        uint256 id = _quote(alice, 1e6);
        uint256 expiry = desk.getQuote(id).expiry;
        vm.warp(block.timestamp + dt);
        vm.prank(alice);
        if (block.timestamp > expiry) {
            vm.expectRevert(ArcFxDesk.QuoteExpired.selector);
        }
        desk.executeQuote(id, 0);
    }

    function testFuzz_LargerInputNeverYieldsLessOutput(uint256 a, uint256 b) public {
        a = bound(a, 1e6, 5e6);
        b = bound(b, a, 5e6);
        assertGe(_net(b, RATE, FEE_BPS), _net(a, RATE, FEE_BPS));
        uint256 ida = _quote(alice, a);
        uint256 idb = _quote(alice, b);
        assertGe(desk.getQuote(idb).minReceived, desk.getQuote(ida).minReceived);
    }

    function testFuzz_SlippageGuard(uint256 minReceived) public {
        uint256 id = _quote(alice, 2e6);
        uint256 payout = _net(2e6, RATE, FEE_BPS);
        vm.prank(alice);
        if (minReceived > payout) {
            vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.SlippageExceeded.selector, payout, minReceived));
        }
        desk.executeQuote(id, minReceived);
    }
}
