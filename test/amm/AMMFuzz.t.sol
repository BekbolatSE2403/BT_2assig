// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/TestToken.sol";
import "src/amm/AMM.sol";

contract AMMFuzzTest is Test {
    TestToken public tokenA;
    TestToken public tokenB;
    AMM public amm;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint8 constant DECIMALS = 18;
    uint256 constant INITIAL_LIQUIDITY = 10000 * 10 ** 18;

    function setUp() public {
        tokenA = new TestToken("Token A", "TKA", DECIMALS);
        tokenB = new TestToken("Token B", "TKB", DECIMALS);

        tokenA.mint(alice, 1_000_000 * 10 ** DECIMALS);
        tokenB.mint(alice, 1_000_000 * 10 ** DECIMALS);
        tokenA.mint(bob, 1_000_000 * 10 ** DECIMALS);
        tokenB.mint(bob, 1_000_000 * 10 ** DECIMALS);

        amm = new AMM(address(tokenA), address(tokenB));

        vm.startPrank(alice);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);
        vm.stopPrank();
    }

    // FIXED: Test that bob's balance increases correctly
    function testFuzz_SwapAForB(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, tokenA.balanceOf(bob));

        uint256 expectedOutput = amm.getAmountOut(amountIn, amm.reserveA(), amm.reserveB());

        if (expectedOutput == 0) return;

        vm.startPrank(bob);
        tokenA.approve(address(amm), amountIn);

        uint256 bobBalanceBefore = tokenB.balanceOf(bob);
        amm.swapAForB(amountIn, 0);
        uint256 bobBalanceAfter = tokenB.balanceOf(bob);
        vm.stopPrank();

        // FIXED: Check that bob received tokens
        assertEq(bobBalanceAfter - bobBalanceBefore, expectedOutput);
    }

    // FIXED: Test that bob's balance increases correctly
    function testFuzz_SwapBForA(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, tokenB.balanceOf(bob));

        uint256 expectedOutput = amm.getAmountOut(amountIn, amm.reserveB(), amm.reserveA());

        if (expectedOutput == 0) return;

        vm.startPrank(bob);
        tokenB.approve(address(amm), amountIn);

        uint256 bobBalanceBefore = tokenA.balanceOf(bob);
        amm.swapBForA(amountIn, 0);
        uint256 bobBalanceAfter = tokenA.balanceOf(bob);
        vm.stopPrank();

        // FIXED: Check that bob received tokens
        assertEq(bobBalanceAfter - bobBalanceBefore, expectedOutput);
    }

    function testFuzz_ProductKNeverDecreases(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, 1000e18);

        uint256 kBefore = amm.reserveA() * amm.reserveB();

        vm.startPrank(bob);
        tokenA.approve(address(amm), amountIn);

        uint256 expectedOutput = amm.getAmountOut(amountIn, amm.reserveA(), amm.reserveB());
        if (expectedOutput > 0) {
            amm.swapAForB(amountIn, 0);
        }
        vm.stopPrank();

        uint256 kAfter = amm.reserveA() * amm.reserveB();

        // k should increase or stay the same (due to fees)
        assertGe(kAfter, kBefore);
    }
}
