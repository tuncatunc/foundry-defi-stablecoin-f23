// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.24;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Tunca following Patrick stable coin course
 * @dev This contract is meant to be managed by DSCEngine
 * @notice
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__InsufficientBalance(uint256 requested, uint256 available);
    error DecentralizedStableCoin__AmountMustBeGreaterThanZero();
    error DecentralizedStableCoin__NoZeroAddress();

    constructor(address _owner) ERC20("Decentralized Stable Coin", "DSC") Ownable(_owner) ERC20Burnable() {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount == 0) {
            revert DecentralizedStableCoin__AmountMustBeGreaterThanZero();
        }

        if (balance < _amount) {
            revert DecentralizedStableCoin__InsufficientBalance(_amount, balance);
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_amount == 0) {
            revert DecentralizedStableCoin__AmountMustBeGreaterThanZero();
        }

        if (_to == address(0)) {
            revert DecentralizedStableCoin__NoZeroAddress();
        }

        _mint(_to, _amount);
        return true;
    }
}
