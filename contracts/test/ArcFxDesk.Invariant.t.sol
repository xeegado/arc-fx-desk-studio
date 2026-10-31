// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ArcFxDeskTestBase, MockToken} from "./ArcFxDesk.Base.t.sol";
import {ArcFxDesk} from "../ArcFxDesk.sol";

/// @dev Drives bounded desk actions and tracks ghost accounting.
contract ArcFxDeskHandler is Test {
    ArcFxDesk public desk;
    MockToken public usdc;
    MockToken public eurc;
    address public owner;
    address[] public actors;

    uint256[] public quoteIds;

    uint256 public ghostUsdcDeposited;
    uint256 public ghostUsdcWithdrawn;
    uint256 public ghostEurcDeposited;
    uint256 public ghostEurcWithdrawn;
    uint256 public ghostSettledIn;
    uint256 public ghostSettledOut;
    uint256 public ghostFees;
    uint256 public ghostSettlements;

    constructor(ArcFxDesk _desk, MockToken _usdc, MockToken _eurc, address _owner, address[] memory _actors) {
        desk = _desk;
        usdc = _usdc;
        eurc = _eurc;
        owner = _owner;
        actors = _actors;
        // seed pre-existing desk balances into ghost deposits (setUp deposited EURC via owner)
        ghostEurcDeposited = _eurc.balanceOf(address(_desk));
        ghostUsdcDeposited = _usdc.balanceOf(address(_desk));
        for (uint256 i; i < _actors.length; i++) {
            _usdc.mint(_actors[i], 1e30);
            vm.prank(_actors[i]);
            _usdc.approve(address(_desk), type(uint256).max);
        }
        _usdc.mint(_owner, 1e30);
        _eurc.mint(_owner, 1e30);
    }

    function quoteCount() external view returns (uint256) {
        return quoteIds.length;
    }

    function request(uint256 actorSeed, uint256 amount) external {
        address a = actors[actorSeed % actors.length];
        amount = bound(amount, 1, desk.maxAmountPerSwap());
        vm.prank(a);
        try desk.requestQuote(amount) returns (uint256 id) {
            quoteIds.push(id);
        } catch {}
    }

    function execute(uint256 idSeed, uint256 minReceivedSeed) external {
        if (quoteIds.length == 0) return;
        uint256 id = quoteIds[idSeed % quoteIds.length];
        ArcFxDesk.Quote memory q = desk.getQuote(id);
        uint256 minReceived = bound(minReceivedSeed, 0, q.minReceived);
        vm.prank(q.user);
        try desk.executeQuote(id, minReceived) {
            ghostSettledIn += q.amountIn;
            ghostSettledOut += q.minReceived;
            ghostFees += q.fee;
            ghostSettlements++;
        } catch {}
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 0, 90));
    }

    function deposit(bool useUsdc, uint256 amount) external {
        amount = bound(amount, 0, 1_000e6);
        MockToken t = useUsdc ? usdc : eurc;
        vm.startPrank(owner);
        t.approve(address(desk), amount);
        desk.depositInventory(address(t), amount);
        vm.stopPrank();
        if (useUsdc) ghostUsdcDeposited += amount;
        else ghostEurcDeposited += amount;
    }

    function withdraw(bool useUsdc, uint256 amount) external {
        MockToken t = useUsdc ? usdc : eurc;
        amount = bound(amount, 0, t.balanceOf(address(desk)));
        vm.prank(owner);
        desk.withdrawInventory(address(t), amount, owner);
        if (useUsdc) ghostUsdcWithdrawn += amount;
        else ghostEurcWithdrawn += amount;
    }

    function setRate(uint256 r) external {
        vm.prank(owner);
        desk.setRate(bound(r, 1e16, 5e18));
    }

    function setFee(uint256 f) external {
        vm.prank(owner);
        desk.setFeeBps(uint16(bound(f, 0, 1000)));
    }

    function setMax(uint256 m) external {
        vm.prank(owner);
        desk.setMaxAmountPerSwap(bound(m, 1, 50e6));
    }

    function togglePause(bool p) external {
        vm.startPrank(owner);
        if (p && !desk.paused()) desk.pause();
        else if (!p && desk.paused()) desk.unpause();
        vm.stopPrank();
    }
}

contract ArcFxDeskInvariantTest is ArcFxDeskTestBase {
    ArcFxDeskHandler internal handler;

    function setUp() public override {
        super.setUp();
        address[] memory actors = new address[](3);
        actors[0] = alice;
        actors[1] = bob;
        actors[2] = carol;
        handler = new ArcFxDeskHandler(desk, usdc, eurc, owner, actors);
        targetContract(address(handler));
    }

    /// USDC held = deposits - withdrawals + USDC collected from settlements.
    function invariant_UsdcReconcilesWithSettlements() public view {
        assertEq(
            usdc.balanceOf(address(desk)),
            handler.ghostUsdcDeposited() + handler.ghostSettledIn() - handler.ghostUsdcWithdrawn()
        );
    }

    /// EURC held = deposits - withdrawals - net EURC paid out in settlements.
    function invariant_EurcReconcilesWithSettlements() public view {
        assertEq(
            eurc.balanceOf(address(desk)),
            handler.ghostEurcDeposited() - handler.ghostSettledOut() - handler.ghostEurcWithdrawn()
        );
    }

    /// Reported inventory equals actual token balances.
    function invariant_InventoryViewMatchesBalances() public view {
        assertEq(desk.inventory(address(usdc)), usdc.balanceOf(address(desk)));
        assertEq(desk.inventory(address(eurc)), eurc.balanceOf(address(desk)));
    }

    /// Number of Executed quotes equals recorded settlements; each executed quote is Open->Executed once.
    function invariant_ExecutedQuotesMatchSettlements() public view {
        uint256 executed;
        uint256 n = handler.quoteCount();
        for (uint256 i; i < n; i++) {
            if (desk.getQuote(handler.quoteIds(i)).status == ArcFxDesk.Status.Executed) executed++;
        }
        assertEq(executed, handler.ghostSettlements());
        assertEq(desk.nextQuoteId(), n + 1);
    }

    /// Bounds on config always hold.
    function invariant_ConfigWithinBounds() public view {
        assertLe(desk.feeBps(), desk.MAX_FEE_BPS());
        assertGt(desk.rate(), 0);
        assertGt(desk.maxAmountPerSwap(), 0);
        assertEq(desk.owner(), owner);
    }
}
