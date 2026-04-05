// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "../src/MyToken.sol";

contract MyTokenInvariantTest is Test {
    MyToken public token;
    address[] public users;
    
    uint8 constant DECIMALS = 18;
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10**DECIMALS;
    uint256 constant NUM_USERS = 5;
    uint256 constant USER_BALANCE = 1000 * 10**DECIMALS;

    function setUp() public {
        token = new MyToken("MyToken", "MTK", DECIMALS);
        
        for(uint i = 0; i < NUM_USERS; i++) {
            address user = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            users.push(user);
            token.transfer(user, USER_BALANCE);
        }
        
        // Tell Foundry which contract to test
        targetContract(address(token));
        
        // REMOVE THE SELECTOR CODE - it's causing the error
        // Just let Foundry call all functions automatically
    }

    /**
     * @dev INVARIANT 1: Total supply is always greater than zero
     */
    function invariant_totalSupplyIsPositive() public view {
        assertGt(token.totalSupply(), 0, "Total supply must be greater than 0");
    }

    /**
     * @dev INVARIANT 2: Sum of all balances equals total supply
     * This is the most important ERC-20 invariant
     */
    function invariant_sumOfAllBalancesEqualsTotalSupply() public view {
        uint256 sum = 0;
        
        // Balance of the test contract (owner)
        sum += token.balanceOf(address(this));
        
        // Balances of all users
        for(uint i = 0; i < users.length; i++) {
            sum += token.balanceOf(users[i]);
        }
        
        // Balance of zero address (burned tokens)
        sum += token.balanceOf(address(0));
        
        assertEq(sum, token.totalSupply(), "Sum of all balances must equal total supply");
    }

    /**
     * @dev INVARIANT 3: No individual balance exceeds total supply
     */
    function invariant_noBalanceExceedsTotalSupply() public view {
        uint256 totalSupply = token.totalSupply();
        
        // Check owner balance
        assertLe(token.balanceOf(address(this)), totalSupply, "Owner balance exceeds total supply");
        
        // Check all user balances
        for(uint i = 0; i < users.length; i++) {
            assertLe(token.balanceOf(users[i]), totalSupply, "User balance exceeds total supply");
        }
        
        // Check zero address
        assertLe(token.balanceOf(address(0)), totalSupply, "Zero address balance exceeds total supply");
    }

    /**
     * @dev INVARIANT 4: Total supply never decreases (only increases via mint)
     */
    uint256 private _previousTotalSupply;
    bool private _isFirstRun = true;
    
    function invariant_totalSupplyMonotonicallyIncreases() public {
        uint256 currentTotalSupply = token.totalSupply();
        
        if (!_isFirstRun) {
            assertGe(currentTotalSupply, _previousTotalSupply, "Total supply should never decrease");
        }
        
        _previousTotalSupply = currentTotalSupply;
        _isFirstRun = false;
    }

    /**
     * @dev INVARIANT 5: Owner balance never exceeds total supply
     */
    function invariant_ownerBalanceWithinLimit() public view {
        assertLe(token.balanceOf(address(this)), token.totalSupply(), "Owner balance exceeds total supply");
    }
}