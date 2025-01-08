// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, Math, SafeERC20} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";

/**
 * @title AAVELoopingStrategy
 * @author Yieldnest
 * @notice This contract is a strategy for AAVE Looping. It is responsible for depositing and withdrawing assets from the
 * vault.
 */
contract AAVELoopingStrategy is Vault {
    /// @notice Storage structure for strategy-specific parameters
    struct StrategyStorage {
        address stakerGateway;
        bool syncDeposit;
        bool syncWithdraw;
        bool hasAllocators;
    }
}
