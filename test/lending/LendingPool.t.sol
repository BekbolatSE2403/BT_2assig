// test/lending/LendingPool.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/lending/LendingPool.sol";
import "src/TestToken.sol";

contract LendingPoolTest is Test {
    LendingPool public pool;
    TestToken public collateralToken;
    TestToken public borrowToken;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public liquidator = makeAddr("liquidator");

    uint8 constant DECIMALS = 18;
    uint256 constant INITIAL_BALANCE = 100_000 * 10 ** DECIMALS;

    function setUp() public {
        collateralToken = new TestToken("Collateral Token", "COL", DECIMALS);
        borrowToken = new TestToken("Borrow Token", "BRW", DECIMALS);

        collateralToken.mint(alice, INITIAL_BALANCE);
        collateralToken.mint(bob, INITIAL_BALANCE);
        borrowToken.mint(alice, INITIAL_BALANCE);
        borrowToken.mint(bob, INITIAL_BALANCE);
        borrowToken.mint(liquidator, 100_000 * 10 ** DECIMALS);

        pool = new LendingPool(address(collateralToken), address(borrowToken));

        borrowToken.mint(address(this), 1_000_000 * 10 ** DECIMALS);
        borrowToken.transfer(address(pool), 1_000_000 * 10 ** DECIMALS);
    }

    function test_Deposit() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);

        (uint256 collateral, uint256 borrowed,,,) = pool.getUserPosition(alice);

        assertEq(collateral, depositAmount);
        assertEq(borrowed, 0);
        vm.stopPrank();
    }

    function test_RevertZeroDeposit() public {
        vm.startPrank(alice);
        vm.expectRevert("Amount must be > 0");
        pool.deposit(0);
        vm.stopPrank();
    }

    function test_BorrowWithinLimit() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 500 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);

        uint256 balanceBefore = borrowToken.balanceOf(alice);
        pool.borrow(borrowAmount);

        (uint256 collateral, uint256 borrowed,,,) = pool.getUserPosition(alice);

        assertEq(collateral, depositAmount);
        assertEq(borrowed, borrowAmount);
        assertEq(borrowToken.balanceOf(alice), balanceBefore + borrowAmount);
        vm.stopPrank();
    }

    function test_RevertBorrowExceedsLTV() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 800 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);

        vm.expectRevert("Exceeds max borrow limit");
        pool.borrow(borrowAmount);
        vm.stopPrank();
    }

    function test_RevertBorrowNoCollateral() public {
        vm.startPrank(alice);
        vm.expectRevert("No collateral deposited");
        pool.borrow(100 * 10 ** DECIMALS);
        vm.stopPrank();
    }

    function test_PartialRepayment() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 500 * 10 ** DECIMALS;
        uint256 repayAmount = 200 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);

        pool.borrow(borrowAmount);
        borrowToken.approve(address(pool), repayAmount);
        pool.repay(repayAmount);

        (, uint256 borrowed,,,) = pool.getUserPosition(alice);

        assertEq(borrowed, borrowAmount - repayAmount);
        vm.stopPrank();
    }

    function test_FullRepayment() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 500 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);

        pool.borrow(borrowAmount);
        borrowToken.approve(address(pool), borrowAmount);
        pool.repayFull();

        (, uint256 borrowed,,,) = pool.getUserPosition(alice);

        assertEq(borrowed, 0);
        vm.stopPrank();
    }

    function test_WithdrawNoDebt() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 withdrawAmount = 500 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);

        pool.withdraw(withdrawAmount);

        (uint256 collateral,,,,) = pool.getUserPosition(alice);

        assertEq(collateral, depositAmount - withdrawAmount);
        vm.stopPrank();
    }

    function test_RevertWithdrawExceedsBalance() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);

        vm.expectRevert("Insufficient collateral");
        pool.withdraw(depositAmount + 1);
        vm.stopPrank();
    }

    function test_RevertWithdrawWithDebtUnhealthy() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 600 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);
        pool.borrow(borrowAmount);

        vm.expectRevert("Health factor too low");
        pool.withdraw(500 * 10 ** DECIMALS);
        vm.stopPrank();
    }

    // FIXED: Interest accrual test using triggerInterestUpdate
    function test_InterestAccrual() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 500 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);
        pool.borrow(borrowAmount);
        vm.stopPrank();

        // Record initial borrowed amount
        (, uint256 borrowedBefore,,,) = pool.getUserPosition(alice);
        assertEq(borrowedBefore, borrowAmount);

        // Warp 1 year into the future
        vm.warp(block.timestamp + 365 days);

        // Manually trigger interest update using test helper
        pool.triggerInterestUpdate(alice);

        // Check borrowed amount after interest
        (, uint256 borrowedAfter,,,) = pool.getUserPosition(alice);

        // Interest should be: 500 * 5% = 25, so total = 525
        console.log("Borrowed before interest:", borrowedBefore / 1e18);
        console.log("Borrowed after interest:", borrowedAfter / 1e18);

        assertApproxEqRel(borrowedAfter, 525 * 10 ** DECIMALS, 0.02e18);
    }

    function test_HealthFactor() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 500 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);
        pool.borrow(borrowAmount);

        uint256 healthFactor = pool.getHealthFactor(alice);

        assertEq(healthFactor, 150);
        vm.stopPrank();
    }

    // FIXED: Liquidation test that actually works
    function test_Liquidation() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 740 * 10 ** DECIMALS; // 74% LTV

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);
        pool.borrow(borrowAmount);
        vm.stopPrank();

        // Check health factor before interest (should be ~101)
        uint256 healthFactorBefore = pool.getHealthFactor(alice);
        console.log("Health factor before interest:", healthFactorBefore);

        // Warp 1 year to accrue interest
        vm.warp(block.timestamp + 365 days);

        // Manually trigger interest update
        pool.triggerInterestUpdate(alice);

        // Check health factor after interest (should be < 100 now)
        uint256 healthFactorAfter = pool.getHealthFactor(alice);
        console.log("Health factor after interest:", healthFactorAfter);

        // Position should now be unhealthy
        assertLt(healthFactorAfter, 100, "Position should be unhealthy after interest");

        // Get initial balances for verification
        uint256 liquidatorBalanceBefore = collateralToken.balanceOf(liquidator);

        // Liquidate
        vm.startPrank(liquidator);
        borrowToken.approve(address(pool), type(uint256).max);
        pool.liquidate(alice);
        vm.stopPrank();

        // Check that Alice's debt is 0 after liquidation
        (, uint256 borrowedAfter,,,) = pool.getUserPosition(alice);
        assertEq(borrowedAfter, 0, "Alice's debt should be 0 after liquidation");

        // Liquidator should have received collateral
        uint256 liquidatorBalanceAfter = collateralToken.balanceOf(liquidator);
        assertGt(liquidatorBalanceAfter, liquidatorBalanceBefore, "Liquidator should receive collateral");
    }

    function test_RevertLiquidateHealthy() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 500 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);
        pool.borrow(borrowAmount);
        vm.stopPrank();

        vm.startPrank(liquidator);
        borrowToken.approve(address(pool), borrowAmount);

        vm.expectRevert("Position is healthy, cannot liquidate");
        pool.liquidate(alice);
        vm.stopPrank();
    }

    function test_GetUserPosition() public {
        uint256 depositAmount = 1000 * 10 ** DECIMALS;
        uint256 borrowAmount = 500 * 10 ** DECIMALS;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);
        pool.borrow(borrowAmount);

        (uint256 collateral, uint256 borrowed,, uint256 maxBorrow, uint256 available) = pool.getUserPosition(alice);

        assertEq(collateral, depositAmount);
        assertEq(borrowed, borrowAmount);
        assertEq(maxBorrow, (depositAmount * 75) / 100);
        assertEq(available, maxBorrow - borrowAmount);
        vm.stopPrank();
    }
}
