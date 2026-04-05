// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MyToken} from "../src/MyToken.sol";

contract MyTokenInvariantTest is Test {
    MyToken public token;
    address[] public users;
    
    uint8 constant DECIMALS = 18;
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10**DECIMALS;

    function setUp() public {
        token = new MyToken("MyToken", "MTK", DECIMALS);
        
        for(uint i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            users.push(user);
            token.transfer(user, 1000 * 10**DECIMALS);
        }
        
        targetContract(address(token));
    }

    function invariant_totalSupplyConstant() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function invariant_balancesWithinTotalSupply() public view {
        uint256 totalSupply = token.totalSupply();
        
        for(uint i = 0; i < users.length; i++) {
            assertLe(token.balanceOf(users[i]), totalSupply);
        }
        assertLe(token.balanceOf(address(this)), totalSupply);
    }
}