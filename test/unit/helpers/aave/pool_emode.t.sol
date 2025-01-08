// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {SetupAAVEPool} from "./SetupAAVEPool.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "lib/aave-v3-origin/src/contracts/dependencies/openzeppelin/contracts/IERC20.sol";

contract TestAAVEPoolEMode is SetupAAVEPool {
    IPool pool;

    function setUp() public {
        // SetupAAVEPool setupAAVEPool = new SetupAAVEPool();
        // setupAAVEPool.deploy();
        // pool = setupAAVEPool.getPool();
        deploy();
        pool = getPool();
        // mimic data of 2025-01-08
        _supplyToPool(tokenListNew.weth, bob, 62_150 ether);
        _supplyToPool(tokenListNew.wstETH, bob, 4_640 ether);
        _supplyToPool(tokenListNew.weETH, bob, 50_050 ether);
        _supplyToPool(tokenListNew.cbETH, bob, 2_820 ether);
    }

    function _supplyToPool(address erc20, address user, uint256 amount) internal {
        vm.startPrank(user);
        IERC20(erc20).approve(address(pool), amount);
        pool.supply(erc20, amount, user, 0);
        vm.stopPrank();
    }

    function testSupplyBorrow() public {
        uint256 supplyAmount = 6 ether;
        uint256 wethBefore = IERC20(tokenListNew.weth).balanceOf(alice);
        uint256 wstETHBefore = IERC20(tokenListNew.wstETH).balanceOf(alice);
        uint256 weETHBefore = IERC20(tokenListNew.weETH).balanceOf(alice);
        uint256 cbETHBefore = IERC20(tokenListNew.cbETH).balanceOf(alice);

        _supplyToPool(tokenListNew.weth, alice, supplyAmount);
        vm.startPrank(alice);
        // Enable eMode for alice
        pool.setUserEMode(1);

        // Borrow 1 of each ETH derivative
        pool.borrow(tokenListNew.cbETH, 1 ether, 2, 0, alice);
        pool.borrow(tokenListNew.weETH, 1 ether, 2, 0, alice);
        pool.borrow(tokenListNew.wstETH, 1 ether, 2, 0, alice);

        assertEq(IERC20(tokenListNew.weth).balanceOf(alice), wethBefore - supplyAmount);
        assertEq(IERC20(tokenListNew.wstETH).balanceOf(alice), wstETHBefore + 1 ether);
        assertEq(IERC20(tokenListNew.weETH).balanceOf(alice), weETHBefore + 1 ether);
        assertEq(IERC20(tokenListNew.cbETH).balanceOf(alice), cbETHBefore + 1 ether);

        vm.stopPrank();
    }
}
