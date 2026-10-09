// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Vexqode} from "../src/Vexqode.sol";

/// @dev Restricts successful operations to a closed set of holders, making conservation measurable.
contract VexqodeHandler is Test {
    Vexqode public immutable token;
    address[4] private actors;
    // Derived only from the initial allocation and requested successful operations.
    // Never copy token getters into this ledger: that would bless incorrect accounting.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Vexqode token_, address[4] memory actors_, uint256 initialBalance) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = initialBalance;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint8 mode) external {
        // Explicitly revisit revocation, infinite approval, and the largest finite approval.
        uint256 amount = mode % 3 == 0 ? 0 : (mode % 3 == 1 ? type(uint256).max : type(uint256).max - 1);
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        if (allowanceBefore < available) available = allowanceBefore;
        amount = bound(amount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordTransfer(owner, to, amount);
        if (allowanceBefore != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // Rejected operations never update the ledger. Invariants check every holder and allowance.
    }

    function transferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function transferFromOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed == type(uint256).max) {
            // Infinite approval cannot be exceeded; revoke it to test that old authority is gone.
            _approve(owner, spender, 0);
            allowed = 0;
        }
        amount = bound(amount, allowed + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 available = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < available) {
            available = expectedAllowance[owner][spender];
        }
        amount = bound(amount, 0, available);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        assertEq(token.balanceOf(from), expectedBalance[from], "sender balance");
        assertEq(token.balanceOf(to), expectedBalance[to], "recipient balance");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract VexqodeInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    Vexqode private token;
    address[4] private actors;
    VexqodeHandler private handler;

    function setUp() public {
        token = new Vexqode();
        actors = [makeAddr("holder0"), makeAddr("holder1"), makeAddr("holder2"), makeAddr("holder3")];
        for (uint256 i; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
        }

        handler = new VexqodeHandler(token, actors, SUPPLY / actors.length);
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, i % 2 == 0 ? SUPPLY / actors.length : type(uint256).max);
        }
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.approveBoundary.selector;
        selectors[4] = handler.transferOverBalance.selector;
        selectors[5] = handler.transferFromOverBalance.selector;
        selectors[6] = handler.transferFromOverAllowance.selector;
        selectors[7] = handler.transferToZero.selector;
        selectors[8] = handler.approveZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndSumOfBalancesStayFixed() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_balancesAndAllowancesMatchSuccessfulCalls() public view {
        for (uint256 i; i < actors.length; ++i) {
            address owner = actors[i];
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "holder ledger");
            assertEq(token.allowance(owner, address(0)), 0, "zero spender approval");
            for (uint256 j; j < actors.length; ++j) {
                address spender = actors[j];
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "approval ledger");
            }
        }
    }

    function test_handlerSequenceExercisesNonzeroSpendingAndRollback() public {
        handler.transfer(0, 1, 1);
        handler.transferFrom(0, 1, 2, 1);
        handler.transferFrom(1, 2, 1, 1); // Delegated self-transfer with infinite approval.
        handler.approveBoundary(0, 1, 0);
        handler.transferFromOverAllowance(0, 1, 2, 1);
        handler.approveBoundary(0, 1, 1);
        handler.transferFromOverAllowance(0, 1, 2, 1); // Revoke an infinite approval.
        handler.approveBoundary(0, 1, 2);
        handler.transferFrom(0, 1, 2, 1); // Maximum finite approval must decrease.
        handler.transferOverBalance(0, 0, type(uint256).max);
        handler.transferFromOverBalance(0, 1, 2, SUPPLY, false);
        handler.transferFromOverBalance(0, 1, 2, type(uint256).max, true);
        handler.transferToZero(0, 1, 1, true);
        handler.transferToZero(0, 1, 0, false);
        handler.approveZeroSpender(0, type(uint256).max);
        invariant_supplyAndSumOfBalancesStayFixed();
        invariant_balancesAndAllowancesMatchSuccessfulCalls();
    }
}
