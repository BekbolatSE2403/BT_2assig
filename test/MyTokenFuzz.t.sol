// test/MyTokenFuzz.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

contract MyTokenFuzzTest is Test {
    MyToken public token;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant DECIMALS = 18; // Объявлено как uint256 для вычислений
    uint256 constant INITIAL_BALANCE = 10000 * 10 ** DECIMALS;

    function setUp() public {
        token = new MyToken("MyToken", "MTK", uint8(DECIMALS)); // Явное преобразование в uint8
        token.transfer(alice, INITIAL_BALANCE);
    }

    // Fuzz тест: transfer с любым корректным amount
    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(alice));

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 bobBalanceBefore = token.balanceOf(bob);

        vm.prank(alice);
        token.transfer(bob, amount);

        assertEq(token.balanceOf(alice), aliceBalanceBefore - amount);
        assertEq(token.balanceOf(bob), bobBalanceBefore + amount);
    }

    // Fuzz тест с несколькими параметрами
    function testFuzz_TransferWithMultipleParams(uint256 amount, address recipient) public {
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(token));
        vm.assume(recipient != alice);

        amount = bound(amount, 1, token.balanceOf(alice));

        uint256 aliceBalanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        token.transfer(recipient, amount);

        assertEq(token.balanceOf(alice), aliceBalanceBefore - amount);
    }
}
