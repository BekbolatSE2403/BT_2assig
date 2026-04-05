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
        
        targetContract(address(token));
    }

    /**
     * @dev INVARIANT 1: Total supply is always greater than zero
     */
    function invariant_totalSupplyIsPositive() public view {
        assertGt(token.totalSupply(), 0);
    }

    /**
     * @dev INVARIANT 2: Sum of tracked balances is LESS THAN OR EQUAL to total supply
     * This is correct because Foundry can transfer to random addresses not in our sum
     */
    function invariant_sumOfTrackedBalancesLessThanOrEqualTotalSupply() public view {
        uint256 sum = 0;
        
        // Balance of the test contract (owner)
        sum += token.balanceOf(address(this));
        
        // Balances of predefined users
        for(uint i = 0; i < users.length; i++) {
            sum += token.balanceOf(users[i]);
        }
        
        // Balance of zero address (burned tokens)
        sum += token.balanceOf(address(0));
        
        // We cannot know all random addresses, so we check <= total supply
        assertLe(sum, token.totalSupply(), "Sum of tracked balances exceeds total supply");
    }

    /**
     * @dev INVARIANT 3: No individual balance exceeds total supply
     */
    function invariant_noBalanceExceedsTotalSupply() public view {
        uint256 totalSupply = token.totalSupply();
        
        assertLe(token.balanceOf(address(this)), totalSupply);
        
        for(uint i = 0; i < users.length; i++) {
            assertLe(token.balanceOf(users[i]), totalSupply);
        }
        
        assertLe(token.balanceOf(address(0)), totalSupply);
    }

    /**
     * @dev INVARIANT 4: Owner balance never exceeds total supply
     */
    function invariant_ownerBalanceWithinLimit() public view {
        assertLe(token.balanceOf(address(this)), token.totalSupply());
    }

    /**
     * @dev INVARIANT 5: Total supply never decreases (only increases via mint)
     */
    uint256 private _previousTotalSupply;
    bool private _isFirstRun = true;
    
    function invariant_totalSupplyMonotonicallyIncreases() public {
        uint256 currentTotalSupply = token.totalSupply();
        
        if (!_isFirstRun) {
            assertGe(currentTotalSupply, _previousTotalSupply);
        }
        
        _previousTotalSupply = currentTotalSupply;
        _isFirstRun = false;
    }
}