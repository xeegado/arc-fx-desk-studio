// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ArcFxDeskTestBase, MockToken} from "./ArcFxDesk.Base.t.sol";
import {ArcFxDesk} from "../ArcFxDesk.sol";

contract ArcFxDeskDeployTest is ArcFxDeskTestBase {
    function test_ConstructorSetsState() public view {
        assertEq(desk.owner(), owner);
        assertEq(address(desk.usdc()), address(usdc));
        assertEq(address(desk.eurc()), address(eurc));
        assertEq(desk.rate(), RATE);
        assertEq(desk.feeBps(), FEE_BPS);
        assertEq(desk.maxAmountPerSwap(), 5e6);
        assertEq(desk.nextQuoteId(), 1);
        assertFalse(desk.paused());
        assertEq(desk.RATE_SCALE(), 1e18);
        assertEq(desk.BPS(), 10_000);
        assertEq(desk.MAX_FEE_BPS(), 1000);
        assertEq(desk.QUOTE_TTL(), 60);
    }

    function test_ConstructorEmitsInitialEvents() public {
        vm.expectEmit(false, false, false, true);
        emit ArcFxDesk.RateUpdated(0, RATE);
        vm.expectEmit(false, false, false, true);
        emit ArcFxDesk.FeeUpdated(0, FEE_BPS);
        vm.expectEmit(false, false, false, true);
        emit ArcFxDesk.MaxAmountUpdated(0, 5e6);
        new ArcFxDesk(owner, address(usdc), address(eurc), RATE, FEE_BPS);
    }

    function test_ConstructorAllowsMaxFee() public {
        ArcFxDesk d = new ArcFxDesk(owner, address(usdc), address(eurc), RATE, 1000);
        assertEq(d.feeBps(), 1000);
    }

    function test_ConstructorAllowsZeroFee() public {
        ArcFxDesk d = new ArcFxDesk(owner, address(usdc), address(eurc), RATE, 0);
        assertEq(d.feeBps(), 0);
    }

    function test_RevertConstructor_ZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ArcFxDesk(address(0), address(usdc), address(eurc), RATE, FEE_BPS);
    }

    function test_RevertConstructor_ZeroUsdc() public {
        vm.expectRevert(ArcFxDesk.ZeroAddress.selector);
        new ArcFxDesk(owner, address(0), address(eurc), RATE, FEE_BPS);
    }

    function test_RevertConstructor_ZeroEurc() public {
        vm.expectRevert(ArcFxDesk.ZeroAddress.selector);
        new ArcFxDesk(owner, address(usdc), address(0), RATE, FEE_BPS);
    }

    function test_RevertConstructor_IdenticalTokens() public {
        vm.expectRevert(ArcFxDesk.IdenticalTokens.selector);
        new ArcFxDesk(owner, address(usdc), address(usdc), RATE, FEE_BPS);
    }

    function test_RevertConstructor_UsdcNot6Decimals() public {
        MockToken bad = new MockToken("Bad", "BAD", 18);
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.InvalidTokenDecimals.selector, address(bad), uint8(18)));
        new ArcFxDesk(owner, address(bad), address(eurc), RATE, FEE_BPS);
    }

    function test_RevertConstructor_EurcNot6Decimals() public {
        MockToken bad = new MockToken("Bad", "BAD", 8);
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.InvalidTokenDecimals.selector, address(bad), uint8(8)));
        new ArcFxDesk(owner, address(usdc), address(bad), RATE, FEE_BPS);
    }

    function test_RevertConstructor_ZeroRate() public {
        vm.expectRevert(ArcFxDesk.InvalidRate.selector);
        new ArcFxDesk(owner, address(usdc), address(eurc), 0, FEE_BPS);
    }

    function test_RevertConstructor_FeeAboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(ArcFxDesk.InvalidFeeBps.selector, uint16(1001)));
        new ArcFxDesk(owner, address(usdc), address(eurc), RATE, 1001);
    }

    // ---------- ownership ----------

    function test_RenounceOwnershipAlwaysReverts_Owner() public {
        vm.prank(owner);
        vm.expectRevert(ArcFxDesk.RenounceDisabled.selector);
        desk.renounceOwnership();
        assertEq(desk.owner(), owner);
    }

    function test_RenounceOwnershipAlwaysReverts_NonOwner() public {
        vm.prank(alice);
        vm.expectRevert(ArcFxDesk.RenounceDisabled.selector);
        desk.renounceOwnership();
        assertEq(desk.owner(), owner);
    }

    function test_RenounceOwnershipReverts_WhilePaused() public {
        vm.prank(owner);
        desk.pause();
        vm.prank(owner);
        vm.expectRevert(ArcFxDesk.RenounceDisabled.selector);
        desk.renounceOwnership();
    }

    function test_TransferOwnership_TwoStep() public {
        vm.expectEmit(true, true, false, false, address(desk));
        emit Ownable2Step.OwnershipTransferStarted(owner, alice);
        vm.prank(owner);
        desk.transferOwnership(alice);
        // not yet transferred
        assertEq(desk.owner(), owner);
        assertEq(desk.pendingOwner(), alice);

        vm.expectEmit(true, true, false, false, address(desk));
        emit Ownable.OwnershipTransferred(owner, alice);
        vm.prank(alice);
        desk.acceptOwnership();
        assertEq(desk.owner(), alice);
        assertEq(desk.pendingOwner(), address(0));

        // old owner lost rights, new owner has them
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        desk.pause();
        vm.prank(alice);
        desk.pause();
        assertTrue(desk.paused());
    }

    function test_PendingOwnerCannotActBeforeAccepting() public {
        vm.prank(owner);
        desk.transferOwnership(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        desk.pause();
    }

    function test_RevertAcceptOwnership_NotPending() public {
        vm.prank(owner);
        desk.transferOwnership(alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        desk.acceptOwnership();
        assertEq(desk.owner(), owner);
    }

    function test_RevertTransferOwnership_NonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        desk.transferOwnership(alice);
    }

    function test_OwnerCanCancelPendingTransfer() public {
        vm.startPrank(owner);
        desk.transferOwnership(alice);
        desk.transferOwnership(address(0));
        vm.stopPrank();
        assertEq(desk.pendingOwner(), address(0));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        desk.acceptOwnership();
    }
}
