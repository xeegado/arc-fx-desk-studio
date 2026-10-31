// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ArcFxDeskTestBase, MockToken} from "./ArcFxDesk.Base.t.sol";
import {ArcFxDesk} from "../ArcFxDesk.sol";

contract ArcFxDeskAdminTest is ArcFxDeskTestBase {
    function _unauth(address who) internal {
        vm.prank(who);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, who));
    }

    // ---------- setRate ----------

    function test_SetRate() public {
        vm.expectEmit(false, false, false, true, address(desk));
        emit ArcFxDesk.RateUpdated(RATE, 1.1e18);
        vm.prank(owner);
        desk.setRate(1.1e18);
        assertEq(desk.rate(), 1.1e18);
    }

    function test_RevertSetRate_Zero() public {
        vm.prank(owner);
        vm.expectRevert(ArcFxDesk.InvalidRate.selector);
        desk.setRate(0);
    }

    function test_RevertSetRate_NonOwner() public {
        _unauth(alice);
        desk.setRate(1e18);
    }

    // ---------- setFeeBps ----------

    function test_SetFeeBps() public {
        vm.expectEmit(false, false, false, true, address(desk));
        emit ArcFxDesk.FeeUpdated(FEE_BPS, 1000);
        vm.prank(owner);
        desk.setFeeBps(1000);
        assertEq(desk.feeBps(), 1000);
    }

    function test_SetFeeBps_Zero() public {
        vm.prank(owner);
        desk.setFeeBps(0);
        assertEq(desk.feeBps(), 0);
    }

    function test_RevertSetFeeBps_AboveMax() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.InvalidFeeBps.selector, uint16(1001)));
        desk.setFeeBps(1001);
    }

    function test_RevertSetFeeBps_NonOwner() public {
        _unauth(alice);
        desk.setFeeBps(10);
    }

    // ---------- setMaxAmountPerSwap ----------

    function test_SetMaxAmountPerSwap() public {
        vm.expectEmit(false, false, false, true, address(desk));
        emit ArcFxDesk.MaxAmountUpdated(5e6, 100e6);
        vm.prank(owner);
        desk.setMaxAmountPerSwap(100e6);
        assertEq(desk.maxAmountPerSwap(), 100e6);
    }

    function test_RevertSetMaxAmountPerSwap_Zero() public {
        vm.prank(owner);
        vm.expectRevert(ArcFxDesk.InvalidMaxAmount.selector);
        desk.setMaxAmountPerSwap(0);
    }

    function test_RevertSetMaxAmountPerSwap_NonOwner() public {
        _unauth(alice);
        desk.setMaxAmountPerSwap(1);
    }

    // ---------- pause / unpause ----------

    function test_PauseAndUnpause() public {
        vm.expectEmit(false, false, false, true, address(desk));
        emit Pausable.Paused(owner);
        vm.prank(owner);
        desk.pause();
        assertTrue(desk.paused());

        vm.expectEmit(false, false, false, true, address(desk));
        emit Pausable.Unpaused(owner);
        vm.prank(owner);
        desk.unpause();
        assertFalse(desk.paused());
    }

    function test_RevertPause_NonOwner() public {
        _unauth(alice);
        desk.pause();
    }

    function test_RevertUnpause_NonOwner() public {
        vm.prank(owner);
        desk.pause();
        _unauth(alice);
        desk.unpause();
    }

    function test_RevertPause_AlreadyPaused() public {
        vm.startPrank(owner);
        desk.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        desk.pause();
        vm.stopPrank();
    }

    function test_RevertUnpause_NotPaused() public {
        vm.prank(owner);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        desk.unpause();
    }

    // ---------- depositInventory ----------

    function test_DepositInventory_BothTokens() public {
        vm.expectEmit(true, true, false, true, address(desk));
        emit ArcFxDesk.InventoryDeposited(address(usdc), owner, 50e6);
        vm.prank(owner);
        desk.depositInventory(address(usdc), 50e6);
        assertEq(desk.inventory(address(usdc)), 50e6);

        vm.expectEmit(true, true, false, true, address(desk));
        emit ArcFxDesk.InventoryDeposited(address(eurc), owner, 25e6);
        vm.prank(owner);
        desk.depositInventory(address(eurc), 25e6);
        assertEq(desk.inventory(address(eurc)), INITIAL_EURC + 25e6);
    }

    function test_DepositInventory_WhilePaused() public {
        vm.startPrank(owner);
        desk.pause();
        desk.depositInventory(address(eurc), 10e6);
        vm.stopPrank();
        assertEq(desk.inventory(address(eurc)), INITIAL_EURC + 10e6);
    }

    function test_RevertDepositInventory_NonOwner() public {
        _unauth(alice);
        desk.depositInventory(address(eurc), 1);
    }

    function test_RevertDepositInventory_UnsupportedToken() public {
        MockToken other = new MockToken("O", "O", 6);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.UnsupportedToken.selector, address(other)));
        desk.depositInventory(address(other), 1);
    }

    function test_RevertDepositInventory_NoAllowance() public {
        vm.startPrank(owner);
        eurc.approve(address(desk), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(desk), 0, 1e6)
        );
        desk.depositInventory(address(eurc), 1e6);
        vm.stopPrank();
    }

    // ---------- withdrawInventory ----------

    function test_WithdrawInventory() public {
        vm.expectEmit(true, true, false, true, address(desk));
        emit ArcFxDesk.InventoryWithdrawn(address(eurc), carol, 100e6);
        vm.prank(owner);
        desk.withdrawInventory(address(eurc), 100e6, carol);
        assertEq(eurc.balanceOf(carol), 100e6);
        assertEq(desk.inventory(address(eurc)), INITIAL_EURC - 100e6);
    }

    function test_WithdrawInventory_Usdc() public {
        vm.startPrank(owner);
        desk.depositInventory(address(usdc), 40e6);
        desk.withdrawInventory(address(usdc), 40e6, carol);
        vm.stopPrank();
        assertEq(usdc.balanceOf(carol), USER_USDC + 40e6);
        assertEq(desk.inventory(address(usdc)), 0);
    }

    function test_WithdrawInventory_WhilePaused() public {
        vm.startPrank(owner);
        desk.pause();
        desk.withdrawInventory(address(eurc), INITIAL_EURC, owner);
        vm.stopPrank();
        assertEq(desk.inventory(address(eurc)), 0);
    }

    function test_RevertWithdrawInventory_NonOwner() public {
        _unauth(alice);
        desk.withdrawInventory(address(eurc), 1, alice);
    }

    function test_RevertWithdrawInventory_UnsupportedToken() public {
        MockToken other = new MockToken("O", "O", 6);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.UnsupportedToken.selector, address(other)));
        desk.withdrawInventory(address(other), 1, owner);
    }

    function test_RevertWithdrawInventory_ZeroRecipient() public {
        vm.prank(owner);
        vm.expectRevert(ArcFxDesk.ZeroAddress.selector);
        desk.withdrawInventory(address(eurc), 1, address(0));
    }

    function test_RevertWithdrawInventory_MoreThanBalance() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(desk), INITIAL_EURC, INITIAL_EURC + 1
            )
        );
        desk.withdrawInventory(address(eurc), INITIAL_EURC + 1, owner);
    }

    // ---------- inventory view ----------

    function test_RevertInventory_UnsupportedToken() public {
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.UnsupportedToken.selector, address(0xBEEF)));
        desk.inventory(address(0xBEEF));
    }

    function test_Inventory_ReportsBalances() public view {
        assertEq(desk.inventory(address(eurc)), INITIAL_EURC);
        assertEq(desk.inventory(address(usdc)), 0);
    }
}
