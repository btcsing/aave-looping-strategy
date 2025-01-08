// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.0;

import {TestnetProceduresETH} from "./TestnetProceduresETH.sol";

contract SetupAAVEPool is TestnetProceduresETH {
    function deploy() public {
        initTestEnvironmentNew();
        vm.startPrank(poolAdmin);
        // set eMode categories
        // ltv: 90%, liquidation threshold: 93%, liquidation bonus: 2%
        contracts.poolConfiguratorProxy.setEModeCategory(1, 9000, 9300, 10200, "eth eMode");
        contracts.poolConfiguratorProxy.setAssetCollateralInEMode(tokenListNew.weth, 1, true);
        contracts.poolConfiguratorProxy.setAssetCollateralInEMode(tokenListNew.wstETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetCollateralInEMode(tokenListNew.weETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetCollateralInEMode(tokenListNew.cbETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetBorrowableInEMode(tokenListNew.weth, 1, true);
        contracts.poolConfiguratorProxy.setAssetBorrowableInEMode(tokenListNew.wstETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetBorrowableInEMode(tokenListNew.weETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetBorrowableInEMode(tokenListNew.cbETH, 1, true);

        emit log_string("deploy AAVE pool weth, wstETH, weETH, cbETH emode SUCCESS!");
        vm.stopPrank();
    }
}
