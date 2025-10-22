// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MockAavePool {
    IERC20 public asset; // USDC
    ERC20Mock public aToken; // aUSDC

    constructor(address _asset, address _aToken) {
        asset = IERC20(_asset);
        aToken = ERC20Mock(_aToken);
    }

    function deposit(address assetAddress, uint256 amount, address onBehalfOf, uint16 /* referralCode */ ) external {
        asset.transferFrom(msg.sender, address(this), amount);

        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address assetAddress, uint256 amount, address to) external returns (uint256) {
        if (amount == type(uint256).max) {
            amount = aToken.balanceOf(msg.sender);
        }

        aToken.burn(msg.sender, amount);

        asset.transfer(to, amount);

        return amount;
    }

    function simulateYield(address user, uint256 yieldAmount) external {
        aToken.mint(user, yieldAmount);
    }
}
