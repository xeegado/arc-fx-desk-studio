// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ArcFxDeskTestBase} from "./ArcFxDesk.Base.t.sol";
import {ArcFxDesk} from "../ArcFxDesk.sol";

contract ArcFxDeskQuoteTest is ArcFxDeskTestBase {
    uint256 internal constant AMT = 2e6;

    // ---------- requestQuote ----------

    function test_RequestQuote_StoresLockedTerms() public {
        uint256 id = _quote(alice, AMT);
        assertEq(id, 1);
        assertEq(desk.nextQuoteId(), 2);

        ArcFxDesk.Quote memory q = desk.getQuote(id);
        uint256 gross = _gross(AMT, RATE);
        uint256 fee = _fee(gross, FEE_BPS);
        assertEq(q.user, alice);
        assertEq(q.amountIn, AMT);
        assertEq(q.rate, RATE);
        assertEq(q.estimatedOut, gross);
        assertEq(q.fee, fee);
        assertEq(q.minReceived, gross - fee);
        assertEq(q.estimatedOut, q.fee + q.minReceived);
        assertEq(q.expiry, block.timestamp + 60);
        assertEq(uint8(q.status), uint8(ArcFxDesk.Status.Open));
        // pure view of mapping getter agrees
        (address u,,,,,,, ArcFxDesk.Status st) = desk.quotes(id);
        assertEq(u, alice);
        assertEq(uint8(st), uint8(ArcFxDesk.Status.Open));
    }

    function test_RequestQuote_DoesNotMoveFundsOrReserve() public {
        uint256 usdcBefore = usdc.balanceOf(alice);
        _quote(alice, AMT);
        assertEq(usdc.balanceOf(alice), usdcBefore);
        assertEq(desk.inventory(address(eurc)), INITIAL_EURC);
        assertEq(desk.inventory(address(usdc)), 0);
    }

    function test_RequestQuote_EmitsQuoteCreated() public {
        uint256 gross = _gross(AMT, RATE);
        uint256 fee = _fee(gross, FEE_BPS);
        vm.expectEmit(true, true, false, true, address(desk));
        emit ArcFxDesk.QuoteCreated(1, alice, AMT, RATE, gross, fee, gross - fee, block.timestamp + 60);
        _quote(alice, AMT);
    }

    function test_RequestQuote_TracksIdsPerUser() public {
        uint256 a1 = _quote(alice, 1e6);
        uint256 b1 = _quote(bob, 1e6);
        uint256 a2 = _quote(alice, 1e6);
        uint256[] memory ids = desk.quoteIdsOf(alice);
        assertEq(ids.length, 2);
        assertEq(ids[0], a1);
        assertEq(ids[1], a2);
        assertEq(desk.quoteCountOf(alice), 2);
        assertEq(desk.quoteCountOf(bob), 1);
        assertEq(desk.quoteIdsOf(bob)[0], b1);
        assertEq(desk.quoteCountOf(carol), 0);
    }

    function test_RequestQuote_ExactlyMaxAmountOk() public {
        uint256 id = _quote(alice, 5e6);
        assertEq(desk.getQuote(id).amountIn, 5e6);
    }

    function test_RequestQuote_ExactInventoryOk() public {
        // withdraw so inventory == payout exactly
        uint256 payout = _net(AMT, RATE, FEE_BPS);
        vm.prank(owner);
        desk.withdrawInventory(address(eurc), INITIAL_EURC - payout, owner);
        uint256 id = _quote(alice, AMT);
        assertEq(desk.getQuote(id).minReceived, payout);
    }

    function test_RevertRequestQuote_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(ArcFxDesk.InvalidAmount.selector);
        desk.requestQuote(0);
    }

    function test_RevertRequestQuote_OverMax() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.AmountExceedsMaximum.selector, 5e6 + 1, 5e6));
        desk.requestQuote(5e6 + 1);
    }

    function test_RevertRequestQuote_Paused() public {
        vm.prank(owner);
        desk.pause();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        desk.requestQuote(AMT);
    }

    function test_RevertRequestQuote_ZeroOutput() public {
        // rate 0.9 -> gross for 1 unit rounds to 0
        vm.prank(alice);
        vm.expectRevert(ArcFxDesk.ZeroOutput.selector);
        desk.requestQuote(1);
    }

    function test_RequestQuote_TinyAmountAtMaxFeeRoundsInUsersFavour() public {
        vm.startPrank(owner);
        desk.setRate(1e18);
        desk.setFeeBps(1000);
        vm.stopPrank();
        // gross=1, fee=floor(1*0.1)=0 -> payout 1, so succeeds (rounding favours user)
        uint256 id = _quote(alice, 1);
        assertEq(desk.getQuote(id).minReceived, 1);
    }

    function test_RevertRequestQuote_InsufficientInventory() public {
        vm.prank(owner);
        desk.withdrawInventory(address(eurc), INITIAL_EURC, owner);
        vm.prank(alice);
        vm.expectRevert(ArcFxDesk.InsufficientInventory.selector);
        desk.requestQuote(AMT);
    }

    function test_RevertRequestQuote_InventoryOneShort() public {
        uint256 payout = _net(AMT, RATE, FEE_BPS);
        vm.prank(owner);
        desk.withdrawInventory(address(eurc), INITIAL_EURC - payout + 1, owner);
        vm.prank(alice);
        vm.expectRevert(ArcFxDesk.InsufficientInventory.selector);
        desk.requestQuote(AMT);
    }

    function test_RevertRequestQuote_UsesUpdatedMax() public {
        vm.prank(owner);
        desk.setMaxAmountPerSwap(1e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.AmountExceedsMaximum.selector, 1e6 + 1, 1e6));
        desk.requestQuote(1e6 + 1);
    }

    // ---------- getQuote ----------

    function test_RevertGetQuote_NotFound() public {
        vm.expectRevert(ArcFxDesk.QuoteNotFound.selector);
        desk.getQuote(1);
        vm.expectRevert(ArcFxDesk.QuoteNotFound.selector);
        desk.getQuote(0);
    }

    // ---------- executeQuote ----------

    function test_Execute_Settles() public {
        uint256 id = _quote(alice, AMT);
        uint256 payout = _net(AMT, RATE, FEE_BPS);
        uint256 fee = _fee(_gross(AMT, RATE), FEE_BPS);

        _exec(alice, id, payout);

        assertEq(usdc.balanceOf(alice), USER_USDC - AMT);
        assertEq(eurc.balanceOf(alice), payout);
        assertEq(desk.inventory(address(usdc)), AMT);
        assertEq(desk.inventory(address(eurc)), INITIAL_EURC - payout);
        assertEq(uint8(desk.getQuote(id).status), uint8(ArcFxDesk.Status.Executed));
        // fee stays in desk: gross = payout + fee left the "liability" side
        assertEq(payout + fee, _gross(AMT, RATE));
    }

    function test_Execute_EmitsSettlementRecorded() public {
        uint256 id = _quote(alice, AMT);
        uint256 payout = _net(AMT, RATE, FEE_BPS);
        uint256 fee = _fee(_gross(AMT, RATE), FEE_BPS);
        vm.expectEmit(true, true, false, true, address(desk));
        emit ArcFxDesk.SettlementRecorded(id, alice, AMT, payout, fee, RATE, block.timestamp);
        _exec(alice, id, 0);
    }

    function test_Execute_AtExactExpirySucceeds() public {
        uint256 id = _quote(alice, AMT);
        vm.warp(desk.getQuote(id).expiry);
        _exec(alice, id, 0);
        assertEq(uint8(desk.getQuote(id).status), uint8(ArcFxDesk.Status.Executed));
    }

    function test_RevertExecute_OneSecondAfterExpiry() public {
        uint256 id = _quote(alice, AMT);
        vm.warp(desk.getQuote(id).expiry + 1);
        vm.prank(alice);
        vm.expectRevert(ArcFxDesk.QuoteExpired.selector);
        desk.executeQuote(id, 0);
        // expired quote stays Open (nothing mutated)
        assertEq(uint8(desk.getQuote(id).status), uint8(ArcFxDesk.Status.Open));
    }

    function test_RevertExecute_Replay() public {
        uint256 id = _quote(alice, AMT);
        _exec(alice, id, 0);
        vm.prank(alice);
        vm.expectRevert(ArcFxDesk.QuoteNotOpen.selector);
        desk.executeQuote(id, 0);
    }

    function test_RevertExecute_NotFound() public {
        vm.prank(alice);
        vm.expectRevert(ArcFxDesk.QuoteNotFound.selector);
        desk.executeQuote(999, 0);
    }

    function test_RevertExecute_NotQuoteOwner() public {
        uint256 id = _quote(alice, AMT);
        vm.prank(bob);
        vm.expectRevert(ArcFxDesk.NotQuoteOwner.selector);
        desk.executeQuote(id, 0);
    }

    function test_RevertExecute_SlippageExceeded() public {
        uint256 id = _quote(alice, AMT);
        uint256 payout = _net(AMT, RATE, FEE_BPS);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.SlippageExceeded.selector, payout, payout + 1));
        desk.executeQuote(id, payout + 1);
    }

    function test_Execute_MinReceivedEqualPayoutOk() public {
        uint256 id = _quote(alice, AMT);
        _exec(alice, id, _net(AMT, RATE, FEE_BPS));
        assertEq(eurc.balanceOf(alice), _net(AMT, RATE, FEE_BPS));
    }

    function test_RevertExecute_Paused() public {
        uint256 id = _quote(alice, AMT);
        vm.prank(owner);
        desk.pause();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        desk.executeQuote(id, 0);
    }

    function test_Execute_AfterUnpauseWithinTtl() public {
        uint256 id = _quote(alice, AMT);
        vm.startPrank(owner);
        desk.pause();
        desk.unpause();
        vm.stopPrank();
        _exec(alice, id, 0);
        assertEq(uint8(desk.getQuote(id).status), uint8(ArcFxDesk.Status.Executed));
    }

    function test_RevertExecute_InsufficientInventory() public {
        uint256 id = _quote(alice, AMT);
        vm.prank(owner);
        desk.withdrawInventory(address(eurc), INITIAL_EURC, owner);
        vm.prank(alice);
        vm.expectRevert(ArcFxDesk.InsufficientInventory.selector);
        desk.executeQuote(id, 0);
    }

    function test_RevertExecute_NoUsdcAllowance_RollsBack() public {
        uint256 id = _quote(alice, AMT);
        vm.prank(alice);
        usdc.approve(address(desk), 0);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(desk), 0, AMT)
        );
        desk.executeQuote(id, 0);
        assertEq(uint8(desk.getQuote(id).status), uint8(ArcFxDesk.Status.Open));
        assertEq(eurc.balanceOf(alice), 0);
    }

    function test_RevertExecute_InsufficientUsdcBalance() public {
        uint256 id = _quote(alice, AMT);
        vm.prank(alice);
        usdc.transfer(bob, USER_USDC); // drain alice
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, AMT)
        );
        desk.executeQuote(id, 0);
    }

    // ---------- locked-quote semantics ----------

    function test_RateFeeMaxChangeAfterQuoteDoesNotAlterLockedQuote() public {
        uint256 id = _quote(alice, AMT);
        ArcFxDesk.Quote memory before_ = desk.getQuote(id);

        vm.startPrank(owner);
        desk.setRate(2e18);
        desk.setFeeBps(1000);
        desk.setMaxAmountPerSwap(1);
        vm.stopPrank();

        ArcFxDesk.Quote memory after_ = desk.getQuote(id);
        assertEq(after_.rate, before_.rate);
        assertEq(after_.fee, before_.fee);
        assertEq(after_.minReceived, before_.minReceived);
        assertEq(after_.amountIn, before_.amountIn);

        _exec(alice, id, before_.minReceived);
        assertEq(eurc.balanceOf(alice), _net(AMT, RATE, FEE_BPS));
        assertEq(desk.inventory(address(usdc)), AMT);
    }

    function test_NewQuoteUsesNewRate() public {
        vm.prank(owner);
        desk.setRate(1.2e18);
        uint256 id = _quote(alice, AMT);
        assertEq(desk.getQuote(id).rate, 1.2e18);
        assertEq(desk.getQuote(id).minReceived, _net(AMT, 1.2e18, FEE_BPS));
    }

    function test_MultipleQuotesSameUserExecuteIndependently() public {
        uint256 id1 = _quote(alice, 1e6);
        uint256 id2 = _quote(alice, 2e6);
        _exec(alice, id2, 0);
        assertEq(uint8(desk.getQuote(id1).status), uint8(ArcFxDesk.Status.Open));
        _exec(alice, id1, 0);
        assertEq(eurc.balanceOf(alice), _net(1e6, RATE, FEE_BPS) + _net(2e6, RATE, FEE_BPS));
    }
}
