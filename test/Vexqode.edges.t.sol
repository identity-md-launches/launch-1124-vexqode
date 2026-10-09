// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Vexqode} from "../src/Vexqode.sol";

/// forge-config: default.fuzz.runs = 1000
contract VexqodeEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Vexqode private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new Vexqode();
        alice = makeAddr("edge-alice");
        bob = makeAddr("edge-bob");
        spender = makeAddr("edge-spender");
    }

    function test_largestFiniteAllowanceDecreasesOnEverySpend() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertTrue(token.transferFrom(address(this), alice, 0));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceCanBeReplacedAndRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        _expectNoRemainingApproval();

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        _expectNoRemainingApproval();
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(alice), 2);
    }

    function test_ownerMustApproveItselfToUseTransferFrom() public {
        assertTrue(token.transfer(alice, 1));
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(alice, alice, 1);
        assertTrue(token.approve(alice, 1));
        assertTrue(token.transferFrom(alice, alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, alice), 0);
        assertTrue(token.transfer(bob, 1));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRevertsWithAndWithoutInfiniteApproval() public {
        uint256 maximum = type(uint256).max;
        bytes memory errorData =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(errorData);
        token.transfer(alice, maximum);
        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(errorData);
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroSpenderRejectsZeroAndMaximumApprovals() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroDelegatedTransferToZeroRevertsForAllApprovalKinds() public {
        uint256[3] memory approvals = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), approvals[i]);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalCanPrecedeFundingAndSurvivesTemporaryEmptyBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);

        vm.prank(bob);
        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function testFuzz_rejectedSpendLeavesApprovalUsable(uint256 balance, uint256 attempt, bool infinite) public {
        balance = bound(balance, 1, SUPPLY);
        attempt = bound(attempt, balance + 1, type(uint256).max);
        uint256 approved = infinite ? type(uint256).max : attempt;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, attempt));
        vm.prank(spender);
        token.transferFrom(alice, bob, attempt);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, balance));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromHandlesAliasedRoles(
        uint8 ownerSeed,
        uint8 spenderSeed,
        uint8 recipientSeed,
        uint256 amount,
        bool infinite
    ) public {
        address[3] memory actors = [address(this), alice, bob];
        uint256 share = SUPPLY / 3;
        assertTrue(token.transfer(alice, share));
        assertTrue(token.transfer(bob, share));
        uint256[3] memory beforeBalances = [SUPPLY - 2 * share, share, share];
        uint256 ownerIndex = ownerSeed % actors.length;
        uint256 recipientIndex = recipientSeed % actors.length;
        address owner = actors[ownerIndex];
        address delegate = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, beforeBalances[ownerIndex]);

        vm.prank(owner);
        assertTrue(token.approve(delegate, infinite ? type(uint256).max : amount));
        vm.prank(delegate);
        assertTrue(token.transferFrom(owner, actors[recipientIndex], amount));

        for (uint256 i; i < actors.length; ++i) {
            uint256 expected = beforeBalances[i];
            if (i == ownerIndex) expected -= amount;
            if (i == recipientIndex) expected += amount;
            assertEq(token.balanceOf(actors[i]), expected);
            for (uint256 j; j < actors.length; ++j) {
                uint256 remaining = infinite && actors[i] == owner && actors[j] == delegate ? type(uint256).max : 0;
                assertEq(token.allowance(actors[i], actors[j]), remaining);
            }
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_finiteApprovalAcrossFullUint256Range(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, type(uint256).max - 1);
        spent = bound(spent, 0, approved < SUPPLY ? approved : SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));
        assertEq(token.allowance(address(this), spender), approved - spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectNoRemainingApproval() private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
    }
}
