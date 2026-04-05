// test/MyTokenMinimal.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

contract MyTokenTest is Test {
    MyToken public token;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint8 constant DECIMALS = 18;

    function setUp() public {
        token = new MyToken("MyToken", "MTK", DECIMALS);
    }

    function test_Name() public view {
        assertEq(token.name(), "MyToken");
    }

    function test_Symbol() public view {
        assertEq(token.symbol(), "MTK");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_Transfer() public {
        uint256 amount = 100 * 10 ** 18;
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
    }

    function test_Approve() public {
        token.approve(alice, 1000);
        assertEq(token.allowance(address(this), alice), 1000);
    }

    function test_TransferFrom() public {
        token.approve(alice, 1000);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 500);
        assertEq(token.balanceOf(bob), 500);
    }
}
