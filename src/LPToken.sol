// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LPToken is ERC20 {
    address public immutable amm;
    
    modifier onlyAMM() {
        require(msg.sender == amm, "LPToken: Only AMM can mint/burn");
        _;
    }
    
    constructor(address _amm) ERC20("AMM Liquidity Provider Token", "AMM-LP") {
        amm = _amm;
    }
    
    function mint(address to, uint256 amount) external onlyAMM {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external onlyAMM {
        _burn(from, amount);
    }
}