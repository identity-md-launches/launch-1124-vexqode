// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Vexqode (VQI)
/// @notice Fixed supply ERC-20 with 18 decimals and no administrative powers.
contract Vexqode is ERC20 {
    /// @notice One billion VQI, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer (including a factory).
    constructor() ERC20("Vexqode", "VQI") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
