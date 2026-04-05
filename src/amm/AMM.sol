// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "src/LPToken.sol";

contract AMM is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    LPToken public immutable lpToken;

    uint256 public constant FEE = 30; // 0.3% (30/10000)
    uint256 public constant FEE_DENOMINATOR = 10000;

    uint256 public reserveA;
    uint256 public reserveB;

    // Events
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokensMinted);

    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokensBurned);

    event Swap(
        address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    constructor(address _tokenA, address _tokenB) Ownable(msg.sender) {
        require(_tokenA != _tokenB, "AMM: Tokens must be different");
        require(_tokenA != address(0) && _tokenB != address(0), "AMM: Invalid token addresses");

        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        lpToken = new LPToken(address(this));
    }

    // Getter for reserves (for external calls)
    function getReserves() public view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }

    // Calculate amount out for a given swap
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "AMM: Amount in must be > 0");
        require(reserveIn > 0 && reserveOut > 0, "AMM: Insufficient liquidity");

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // Add liquidity to the pool
    function addLiquidity(uint256 amountA, uint256 amountB, uint256 minLPTokens)
        external
        nonReentrant
        returns (uint256 lpTokensMinted)
    {
        require(amountA > 0 && amountB > 0, "AMM: Amounts must be > 0");

        // Transfer tokens from user to contract
        tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        tokenB.safeTransferFrom(msg.sender, address(this), amountB);

        uint256 totalLPSupply = lpToken.totalSupply();

        if (totalLPSupply == 0) {
            // First liquidity provider
            lpTokensMinted = _sqrt(amountA * amountB);
        } else {
            // Subsequent providers - must maintain ratio
            uint256 expectedAmountB = (amountA * reserveB) / reserveA;
            require(amountB >= expectedAmountB, "AMM: Incorrect B amount for ratio");

            uint256 liquidityA = (amountA * totalLPSupply) / reserveA;
            uint256 liquidityB = (amountB * totalLPSupply) / reserveB;
            lpTokensMinted = liquidityA < liquidityB ? liquidityA : liquidityB;
        }

        require(lpTokensMinted >= minLPTokens, "AMM: Slippage protection");

        // Update reserves
        reserveA += amountA;
        reserveB += amountB;

        // Mint LP tokens to provider
        lpToken.mint(msg.sender, lpTokensMinted);

        emit LiquidityAdded(msg.sender, amountA, amountB, lpTokensMinted);
    }

    // Remove liquidity from the pool
    function removeLiquidity(uint256 lpTokenAmount, uint256 minAmountA, uint256 minAmountB)
        external
        nonReentrant
        returns (uint256 amountA, uint256 amountB)
    {
        require(lpTokenAmount > 0, "AMM: LP token amount must be > 0");

        uint256 totalLPSupply = lpToken.totalSupply();

        // Calculate amounts based on LP token share
        amountA = (lpTokenAmount * reserveA) / totalLPSupply;
        amountB = (lpTokenAmount * reserveB) / totalLPSupply;

        require(amountA >= minAmountA, "AMM: Insufficient A output");
        require(amountB >= minAmountB, "AMM: Insufficient B output");

        // Burn LP tokens from user
        lpToken.burn(msg.sender, lpTokenAmount);

        // Update reserves
        reserveA -= amountA;
        reserveB -= amountB;

        // Transfer tokens back to user
        tokenA.safeTransfer(msg.sender, amountA);
        tokenB.safeTransfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpTokenAmount);
    }

    // Swap tokenA for tokenB
    function swapAForB(uint256 amountIn, uint256 minAmountOut) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "AMM: Amount in must be > 0");

        amountOut = getAmountOut(amountIn, reserveA, reserveB);
        require(amountOut >= minAmountOut, "AMM: Slippage protection");

        // Transfer tokenA from user
        tokenA.safeTransferFrom(msg.sender, address(this), amountIn);

        // Update reserves
        reserveA += amountIn;
        reserveB -= amountOut;

        // Transfer tokenB to user
        tokenB.safeTransfer(msg.sender, amountOut);

        emit Swap(msg.sender, address(tokenA), address(tokenB), amountIn, amountOut);
    }

    // Swap tokenB for tokenA
    function swapBForA(uint256 amountIn, uint256 minAmountOut) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "AMM: Amount in must be > 0");

        amountOut = getAmountOut(amountIn, reserveB, reserveA);
        require(amountOut >= minAmountOut, "AMM: Slippage protection");

        // Transfer tokenB from user
        tokenB.safeTransferFrom(msg.sender, address(this), amountIn);

        // Update reserves
        reserveB += amountIn;
        reserveA -= amountOut;

        // Transfer tokenA to user
        tokenA.safeTransfer(msg.sender, amountOut);

        emit Swap(msg.sender, address(tokenB), address(tokenA), amountIn, amountOut);
    }

    // Square root function for initial LP minting
    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
