// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDT
/// @notice Minimal ERC20 stablecoin used in tests, built on top of OpenZeppelin ERC20.
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock Tether USD", "mUSDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
