// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Token} from "./Token.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract VaultUSDC {
    error VaultUSDC__InsuficientAmount();
    event deposited(address user, uint256 amount);

    IERC20 public token;

    mapping(address user => uint256 amount) public s_tokenDeposits;


    constructor() {
        //USDC sepolia testnet address
        token = IERC20(0x8267cF9254734C6Eb452a7bb9AAF97B392258b21);
    }

    function deposit(uint256 amount) public {
        if(amount <= 0) {
            revert VaultUSDC__InsuficientAmount();
         }
        token.transferFrom(msg.sender, address(this), amount);
        s_tokenDeposits[msg.sender] += amount;
        emit deposited(msg.sender, amount);
    }


    




}