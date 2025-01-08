/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";

/**
 * @title ETHRateProvider
 * @author Yieldnest
 * @notice Provides the rate of BNB for the Yieldnest Kernel
 */
contract ETHRateProvider {
    error UnsupportedAsset(address asset);

    /**
     * @notice Returns the rate of the given asset
     * @param asset The asset to get the rate for
     * @return The rate of the asset
     */
    function getRate(address asset) public pure returns (uint256) {
        if (asset == MC.WETH) {
            return 1e18;
        }

        revert UnsupportedAsset(asset);
    }
}
