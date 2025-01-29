/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {IAaveOracle} from "lib/aave-v3-origin/src/contracts/interfaces/IAaveOracle.sol";
import {Math} from "lib/yieldnest-vault/src/Common.sol";
import {console} from "forge-std/console.sol";
/**
 * @title ETHRateProvider
 * @author Yieldnest
 * @notice Provides the rate of BNB for the Yieldnest Kernel
 */

contract ETHRateProvider {
    using Math for uint256;

    error UnsupportedAsset(address asset);
    error UnsupportedBaseCurrencyUnit();

    IAaveOracle aaveOracle;

    constructor(address _aaveOracle) {
        aaveOracle = IAaveOracle(_aaveOracle);
        if (aaveOracle.BASE_CURRENCY_UNIT() != 1e8) {
            revert UnsupportedBaseCurrencyUnit();
        }
    }

    /**
     * @notice Returns the rate of the given asset
     * @param asset The asset to get the rate for
     * @return The rate of the asset
     */
    function getRate(address asset) public view returns (uint256) {
        if (asset == MC.WETH || asset == MC.ETH) {
            return 1e18;
        }

        // aave oracle returns price in 1e8 (8 decimals) in USD
        uint256 price = aaveOracle.getAssetPrice(asset);
        if (price == 0) {
            revert UnsupportedAsset(asset);
        }
        uint256 ethPrice = aaveOracle.getAssetPrice(MC.WETH);
        uint256 rate = price.mulDiv(1e18, ethPrice, Math.Rounding.Floor);
        return rate;
    }
}
