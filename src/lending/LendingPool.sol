// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LendingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateralToken;
    IERC20 public immutable borrowToken;

    // Constants
    uint256 public constant LTV = 75; // 75% Loan-to-Value ratio
    uint256 public constant LIQUIDATION_THRESHOLD = 80; // 80% liquidation threshold
    uint256 public constant INTEREST_RATE_PER_YEAR = 5; // 5% APR
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // User position struct
    struct Position {
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 lastInterestUpdate;
    }

    mapping(address => Position) public positions;

    uint256 public totalCollateral;
    uint256 public totalBorrowed;

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 collateralSeized, uint256 debtRepaid);

    constructor(address _collateralToken, address _borrowToken) Ownable(msg.sender) {
        require(_collateralToken != address(0), "Invalid collateral token");
        require(_borrowToken != address(0), "Invalid borrow token");
        require(_collateralToken != _borrowToken, "Tokens must be different");

        collateralToken = IERC20(_collateralToken);
        borrowToken = IERC20(_borrowToken);
    }

    // Update interest for a user before any action
    modifier updateInterest(address user) {
        _updateInterest(user);
        _;
    }

    function _updateInterest(address user) internal {
        Position storage pos = positions[user];
        if (pos.borrowedAmount > 0) {
            uint256 interest = _calculateInterest(pos.borrowedAmount, pos.lastInterestUpdate);
            pos.borrowedAmount += interest;
            totalBorrowed += interest;
        }
        pos.lastInterestUpdate = block.timestamp;
    }

    function _calculateInterest(uint256 amount, uint256 lastUpdate) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdate;
        if (timeElapsed == 0) return 0;

        uint256 interest = (amount * INTEREST_RATE_PER_YEAR * timeElapsed) / (SECONDS_PER_YEAR * 100);
        return interest;
    }

    // Calculate health factor for a user
    function getHealthFactor(address user) public view returns (uint256) {
        Position memory pos = positions[user];
        if (pos.collateralAmount == 0) return type(uint256).max;

        uint256 collateralValue = pos.collateralAmount; // Assume 1:1 price ratio for simplicity
        uint256 debtValue = pos.borrowedAmount;

        if (debtValue == 0) return type(uint256).max;

        return (collateralValue * LTV * 100) / (debtValue * 100);
    }

    function isHealthy(address user) public view returns (bool) {
        return getHealthFactor(user) >= 100;
    }

    // Deposit collateral
    function deposit(uint256 amount) external nonReentrant updateInterest(msg.sender) {
        require(amount > 0, "Amount must be > 0");

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        positions[msg.sender].collateralAmount += amount;
        totalCollateral += amount;

        emit Deposited(msg.sender, amount);
    }

    // Withdraw collateral
    function withdraw(uint256 amount) external nonReentrant updateInterest(msg.sender) {
        require(amount > 0, "Amount must be > 0");
        require(positions[msg.sender].collateralAmount >= amount, "Insufficient collateral");

        // Check health factor after withdrawal
        uint256 newCollateral = positions[msg.sender].collateralAmount - amount;
        uint256 borrowed = positions[msg.sender].borrowedAmount;

        if (borrowed > 0) {
            uint256 newHealthFactor = (newCollateral * LTV * 100) / (borrowed * 100);
            require(newHealthFactor >= 100, "Health factor too low");
        }

        positions[msg.sender].collateralAmount = newCollateral;
        totalCollateral -= amount;

        collateralToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // Borrow against collateral
    function borrow(uint256 amount) external nonReentrant updateInterest(msg.sender) {
        require(amount > 0, "Amount must be > 0");

        Position storage pos = positions[msg.sender];
        require(pos.collateralAmount > 0, "No collateral deposited");

        uint256 maxBorrow = (pos.collateralAmount * LTV) / 100;
        require(pos.borrowedAmount + amount <= maxBorrow, "Exceeds max borrow limit");

        pos.borrowedAmount += amount;
        totalBorrowed += amount;

        borrowToken.safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount);
    }

    // Repay borrowed amount
    function repay(uint256 amount) external nonReentrant updateInterest(msg.sender) {
        require(amount > 0, "Amount must be > 0");

        Position storage pos = positions[msg.sender];
        require(pos.borrowedAmount > 0, "No debt to repay");

        uint256 repayAmount = amount > pos.borrowedAmount ? pos.borrowedAmount : amount;

        pos.borrowedAmount -= repayAmount;
        totalBorrowed -= repayAmount;

        borrowToken.safeTransferFrom(msg.sender, address(this), repayAmount);

        emit Repaid(msg.sender, repayAmount);
    }

    // Repay full debt
    function repayFull() external nonReentrant updateInterest(msg.sender) {
        Position storage pos = positions[msg.sender];
        require(pos.borrowedAmount > 0, "No debt to repay");

        uint256 debt = pos.borrowedAmount;

        pos.borrowedAmount = 0;
        totalBorrowed -= debt;

        borrowToken.safeTransferFrom(msg.sender, address(this), debt);

        emit Repaid(msg.sender, debt);
    }

    // Add this function for testing purposes only
    function triggerInterestUpdate(address user) external {
        _updateInterest(user);
    }

    // Liquidate an undercollateralized position
    function liquidate(address user) external nonReentrant updateInterest(user) {
        require(!isHealthy(user), "Position is healthy, cannot liquidate");

        Position storage pos = positions[user];
        require(pos.collateralAmount > 0, "No collateral to liquidate");

        uint256 debt = pos.borrowedAmount;
        uint256 collateralToSeize = (debt * 100) / LTV; // Seize enough collateral to cover debt + buffer

        if (collateralToSeize > pos.collateralAmount) {
            collateralToSeize = pos.collateralAmount;
        }

        // Update user position
        pos.borrowedAmount = 0;
        pos.collateralAmount -= collateralToSeize;
        totalCollateral -= collateralToSeize;
        totalBorrowed -= debt;

        // Liquidator repays debt and receives collateral
        borrowToken.safeTransferFrom(msg.sender, address(this), debt);
        collateralToken.safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(user, msg.sender, collateralToSeize, debt);
    }

    // Get user position details
    function getUserPosition(address user)
        external
        view
        returns (
            uint256 collateral,
            uint256 borrowed,
            uint256 healthFactor,
            uint256 maxBorrow,
            uint256 availableToBorrow
        )
    {
        Position memory pos = positions[user];
        collateral = pos.collateralAmount;
        borrowed = pos.borrowedAmount;
        healthFactor = getHealthFactor(user);
        maxBorrow = (collateral * LTV) / 100;
        availableToBorrow = borrowed >= maxBorrow ? 0 : maxBorrow - borrowed;
    }
}
