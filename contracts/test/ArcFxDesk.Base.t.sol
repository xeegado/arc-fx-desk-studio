// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ArcFxDesk} from "../ArcFxDesk.sol";

/// @dev Minimal mock token with configurable decimals and open mint.
contract MockToken is ERC20 {
    uint8 private immutable _dec;

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _dec = d;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

abstract contract ArcFxDeskTestBase is Test {
    ArcFxDesk internal desk;
    MockToken internal usdc;
    MockToken internal eurc;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant RATE = 0.9e18; // 0.9 EURC per USDC
    uint16 internal constant FEE_BPS = 30; // 0.30%
    uint256 internal constant INITIAL_EURC = 1_000e6;
    uint256 internal constant USER_USDC = 1_000e6;

    function setUp() public virtual {
        usdc = new MockToken("Mock USDC", "USDC", 6);
        eurc = new MockToken("Mock EURC", "EURC", 6);
        desk = new ArcFxDesk(owner, address(usdc), address(eurc), RATE, FEE_BPS);

        eurc.mint(owner, 10_000e6);
        usdc.mint(owner, 10_000e6);
        vm.startPrank(owner);
        eurc.approve(address(desk), type(uint256).max);
        usdc.approve(address(desk), type(uint256).max);
        desk.depositInventory(address(eurc), INITIAL_EURC);
        vm.stopPrank();

        address[3] memory users = [alice, bob, carol];
        for (uint256 i; i < users.length; i++) {
            usdc.mint(users[i], USER_USDC);
            vm.prank(users[i]);
            usdc.approve(address(desk), type(uint256).max);
        }
    }

    // ---------- helpers ----------

    function _gross(uint256 amountIn, uint256 rate_) internal pure returns (uint256) {
        return (amountIn * rate_) / 1e18;
    }

    function _fee(uint256 gross, uint256 bps) internal pure returns (uint256) {
        return (gross * bps) / 10_000;
    }

    function _net(uint256 amountIn, uint256 rate_, uint256 bps) internal pure returns (uint256) {
        uint256 g = _gross(amountIn, rate_);
        return g - _fee(g, bps);
    }

    function _quote(address user, uint256 amountIn) internal returns (uint256 id) {
        vm.prank(user);
        id = desk.requestQuote(amountIn);
    }

    function _exec(address user, uint256 id, uint256 minReceived) internal {
        vm.prank(user);
        desk.executeQuote(id, minReceived);
    }
}
