/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";

contract MockRateProvider {
    error UnsupportedAsset(address asset);

    mapping(address => uint256) public rates;

    function addRate(address asset, uint256 rate) public {
        rates[asset] = rate;
    }

    function getRate(address asset) public view returns (uint256) {
        uint256 rate = rates[asset];
        if (rate != 0) {
            return rate;
        }

        revert UnsupportedAsset(asset);
    }
}
