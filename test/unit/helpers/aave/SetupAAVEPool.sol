// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.0;

import {TestnetProceduresETH} from "./TestnetProceduresETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";

contract SetupAAVEPool is TestnetProceduresETH {
    // for mimic supply and borrow
    address public aaveWhale = address(0x0aabe);

    uint8 public constant EModeCategory = 1;

    function deploy() public {
        initTestEnvironmentNew();
        vm.startPrank(poolAdmin);
        // set eMode categories
        // ltv: 90%, liquidation threshold: 93%, liquidation bonus: 2%
        contracts.poolConfiguratorProxy.setEModeCategory(EModeCategory, 9000, 9300, 10200, "eth eMode");
        contracts.poolConfiguratorProxy.setAssetCollateralInEMode(tokenListNew.weth, 1, true);
        contracts.poolConfiguratorProxy.setAssetCollateralInEMode(tokenListNew.wstETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetCollateralInEMode(tokenListNew.weETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetCollateralInEMode(tokenListNew.cbETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetBorrowableInEMode(tokenListNew.weth, 1, true);
        contracts.poolConfiguratorProxy.setAssetBorrowableInEMode(tokenListNew.wstETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetBorrowableInEMode(tokenListNew.weETH, 1, true);
        contracts.poolConfiguratorProxy.setAssetBorrowableInEMode(tokenListNew.cbETH, 1, true);
        // mock pool supply and borrow
        mockPoolSupplyAndBorrow();
        // emit log_string("deploy AAVE pool weth, wstETH, weETH, cbETH emode SUCCESS!");
        vm.stopPrank();
    }

    function mockPoolSupplyAndBorrow() internal {
        uint256 amount = 10_000_000 ether;
        deal(address(weth), aaveWhale, amount);
        deal(address(tokenListNew.wstETH), aaveWhale, amount);
        deal(address(tokenListNew.weETH), aaveWhale, amount);
        deal(address(tokenListNew.cbETH), aaveWhale, amount);

        IPool pool = IPool(getPool());

        vm.startPrank(aaveWhale);
        weth.approve(address(pool), UINT256_MAX);
        IERC20(tokenListNew.wstETH).approve(address(pool), UINT256_MAX);
        IERC20(tokenListNew.weETH).approve(address(pool), UINT256_MAX);
        IERC20(tokenListNew.cbETH).approve(address(pool), UINT256_MAX);
        vm.stopPrank();

        // supply to pool, mimic data of 2025-01-08
        _supplyToPool(tokenListNew.weth, aaveWhale, 1_760_000 ether);
        _supplyToPool(tokenListNew.wstETH, aaveWhale, 1_020_000 ether);
        _supplyToPool(tokenListNew.weETH, aaveWhale, 1_210_000 ether);
        _supplyToPool(tokenListNew.cbETH, aaveWhale, 5_710 ether);

        vm.startPrank(aaveWhale);
        pool.borrow(tokenListNew.weth, 1_490_000 ether, 2, 0, aaveWhale);
        pool.borrow(tokenListNew.wstETH, 267_180 ether, 2, 0, aaveWhale);
        pool.borrow(tokenListNew.weETH, 6_956 ether, 2, 0, aaveWhale);
        pool.borrow(tokenListNew.cbETH, 954 ether, 2, 0, aaveWhale);
        vm.stopPrank();
    }

    function _supplyToPool(address erc20, address user, uint256 amount) internal {
        vm.startPrank(user);
        IPool pool = IPool(getPool());
        IERC20(erc20).approve(address(pool), amount);
        pool.supply(erc20, amount, user, 0);
        vm.stopPrank();
    }
}
