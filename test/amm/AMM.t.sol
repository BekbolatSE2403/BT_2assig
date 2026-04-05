// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/TestToken.sol";
import "src/amm/AMM.sol";

contract AMMTest is Test {
    TestToken public tokenA;
    TestToken public tokenB;
    AMM public amm;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 constant INITIAL_BALANCE = 100_000 * 10 ** 18;
    uint8 constant DECIMALS = 18;

    function setUp() public {
        tokenA = new TestToken("Token A", "TKA", DECIMALS);
        tokenB = new TestToken("Token B", "TKB", DECIMALS);

        tokenA.mint(alice, INITIAL_BALANCE);
        tokenA.mint(bob, INITIAL_BALANCE);
        tokenB.mint(alice, INITIAL_BALANCE);
        tokenB.mint(bob, INITIAL_BALANCE);

        amm = new AMM(address(tokenA), address(tokenB));
    }

    function test_AddInitialLiquidity() public {
        uint256 amountA = 1000 * 10 ** DECIMALS;
        uint256 amountB = 1000 * 10 ** DECIMALS;

        vm.startPrank(alice);
        tokenA.approve(address(amm), amountA);
        tokenB.approve(address(amm), amountB);

        uint256 lpTokens = amm.addLiquidity(amountA, amountB, 0);

        assertGt(lpTokens, 0);
        assertEq(amm.reserveA(), amountA);
        assertEq(amm.reserveB(), amountB);
        assertEq(amm.lpToken().balanceOf(alice), lpTokens);
        vm.stopPrank();
    }

    // FIXED: Add approval for second deposit
    function test_AddMoreLiquidity() public {
        vm.startPrank(alice);

        // First deposit
        tokenA.approve(address(amm), 1000e18);
        tokenB.approve(address(amm), 1000e18);
        amm.addLiquidity(1000e18, 1000e18, 0);

        // FIXED: Need to approve again for second deposit
        tokenA.approve(address(amm), 500e18);
        tokenB.approve(address(amm), 500e18);

        uint256 lpBefore = amm.lpToken().balanceOf(alice);
        amm.addLiquidity(500e18, 500e18, 0);
        uint256 lpAfter = amm.lpToken().balanceOf(alice);

        assertGt(lpAfter, lpBefore);
        vm.stopPrank();
    }

    // FIXED: Correct expected value calculation
    function test_GetAmountOut() public view {
        uint256 amountIn = 100e18;
        uint256 reserveIn = 1000e18;
        uint256 reserveOut = 1000e18;

        uint256 amountOut = amm.getAmountOut(amountIn, reserveIn, reserveOut);

        // Formula: amountOut = (amountIn * 0.997 * reserveOut) / (reserveIn + amountIn * 0.997)
        // For 100 input with 1000 reserves: ~90.66 output
        uint256 expected = 90661089388014913158; // This is correct for 0.3% fee

        assertEq(amountOut, expected);
        assertLt(amountOut, amountIn);
    }

    function test_SwapAForB() public {
        // Add initial liquidity
        vm.startPrank(alice);
        tokenA.approve(address(amm), 1000e18);
        tokenB.approve(address(amm), 1000e18);
        amm.addLiquidity(1000e18, 1000e18, 0);
        vm.stopPrank();

        // Bob swaps A for B
        vm.startPrank(bob);
        uint256 swapAmount = 100e18;
        tokenA.approve(address(amm), swapAmount);

        uint256 expectedOutput = amm.getAmountOut(swapAmount, 1000e18, 1000e18);

        // FIXED: Check bob's balance, not alice
        uint256 bobBalanceBBefore = tokenB.balanceOf(bob);
        amm.swapAForB(swapAmount, 0);
        uint256 bobBalanceBAfter = tokenB.balanceOf(bob);

        assertEq(bobBalanceBAfter - bobBalanceBBefore, expectedOutput);
        vm.stopPrank();
    }

    function test_SwapBForA() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 1000e18);
        tokenB.approve(address(amm), 1000e18);
        amm.addLiquidity(1000e18, 1000e18, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 swapAmount = 100e18;
        tokenB.approve(address(amm), swapAmount);

        uint256 expectedOutput = amm.getAmountOut(swapAmount, 1000e18, 1000e18);

        uint256 bobBalanceABefore = tokenA.balanceOf(bob);
        amm.swapBForA(swapAmount, 0);
        uint256 bobBalanceAAfter = tokenA.balanceOf(bob);

        assertEq(bobBalanceAAfter - bobBalanceABefore, expectedOutput);
        vm.stopPrank();
    }

    function test_RemoveLiquidityPartial() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 1000e18);
        tokenB.approve(address(amm), 1000e18);
        amm.addLiquidity(1000e18, 1000e18, 0);

        uint256 lpBalance = amm.lpToken().balanceOf(alice);
        uint256 lpToRemove = lpBalance / 2;

        uint256 reserveABefore = amm.reserveA();
        uint256 reserveBBefore = amm.reserveB();

        (uint256 amountA, uint256 amountB) = amm.removeLiquidity(lpToRemove, 0, 0);

        assertGt(amountA, 0);
        assertGt(amountB, 0);
        assertEq(amm.reserveA(), reserveABefore - amountA);
        assertEq(amm.reserveB(), reserveBBefore - amountB);
        vm.stopPrank();
    }

    function test_RemoveLiquidityFull() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 1000e18);
        tokenB.approve(address(amm), 1000e18);
        amm.addLiquidity(1000e18, 1000e18, 0);

        uint256 lpBalance = amm.lpToken().balanceOf(alice);

        (uint256 amountA, uint256 amountB) = amm.removeLiquidity(lpBalance, 0, 0);

        assertGt(amountA, 0);
        assertGt(amountB, 0);
        assertEq(amm.reserveA(), 0);
        assertEq(amm.reserveB(), 0);
        assertEq(amm.lpToken().balanceOf(alice), 0);
        vm.stopPrank();
    }

    function test_KConstantAfterSwap() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 1000e18);
        tokenB.approve(address(amm), 1000e18);
        amm.addLiquidity(1000e18, 1000e18, 0);

        uint256 kBefore = amm.reserveA() * amm.reserveB();

        tokenA.approve(address(amm), 100e18);
        amm.swapAForB(100e18, 0);

        uint256 kAfter = amm.reserveA() * amm.reserveB();

        // k should increase due to fee
        assertGt(kAfter, kBefore);
        vm.stopPrank();
    }

    function test_SlippageProtectionSwap() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 1000e18);
        tokenB.approve(address(amm), 1000e18);
        amm.addLiquidity(1000e18, 1000e18, 0);

        uint256 expectedOutput = amm.getAmountOut(100e18, 1000e18, 1000e18);
        uint256 minOutput = expectedOutput + 1;

        vm.expectRevert("AMM: Slippage protection");
        amm.swapAForB(100e18, minOutput);
        vm.stopPrank();
    }

    // FIXED: Proper allowance before slippage test
    function test_SlippageProtectionAddLiquidity() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 1000e18);
        tokenB.approve(address(amm), 1000e18);
        amm.addLiquidity(1000e18, 1000e18, 0);

        // FIXED: Approve tokens for second deposit
        tokenA.approve(address(amm), 500e18);
        tokenB.approve(address(amm), 500e18);

        vm.expectRevert("AMM: Slippage protection");
        amm.addLiquidity(500e18, 500e18, 1000000e18);
        vm.stopPrank();
    }

    function test_RevertZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert("AMM: Amounts must be > 0");
        amm.addLiquidity(0, 1000e18, 0);

        vm.expectRevert("AMM: Amounts must be > 0");
        amm.addLiquidity(1000e18, 0, 0);
        vm.stopPrank();
    }
}
