// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {SetupAAVEPool} from "./SetupAAVEPool.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "lib/aave-v3-origin/src/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IAToken} from "lib/aave-v3-origin/src/contracts/interfaces/IAToken.sol";
import {PercentageMath} from "lib/aave-v3-origin/src/contracts/protocol/libraries/math/PercentageMath.sol";
import {EtchUtils} from "../EtchUtils.sol";
import {DataTypes} from "lib/aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";

contract TestAAVEPoolEMode is SetupAAVEPool, EtchUtils {
    using PercentageMath for uint256;

    IPool pool;
    // only support InterestRateMode.VARIABLE now, see code DataTypes.sol
    uint256 public constant INTEREST_RATE_MODE = uint256(DataTypes.InterestRateMode.VARIABLE);
    // only support 0 now
    uint16 public constant REFERAL_CODE = 0;

    function setUp() public {
        mockAll();
        deploy();
        pool = IPool(getPool());

        deal(address(tokenListNew.weth), alice, 100_000 ether);
    }

    function test_SupplyBorrow() public {
        uint256 supplyAmount = 6 ether;
        uint256 wethBefore = IERC20(tokenListNew.weth).balanceOf(alice);
        uint256 wstETHBefore = IERC20(tokenListNew.wstETH).balanceOf(alice);
        uint256 weETHBefore = IERC20(tokenListNew.weETH).balanceOf(alice);
        uint256 cbETHBefore = IERC20(tokenListNew.cbETH).balanceOf(alice);

        _supplyToPool(tokenListNew.weth, alice, supplyAmount);
        vm.startPrank(alice);
        // Enable eMode for alice
        pool.setUserEMode(setupAAVE.EModeCategory());

        // Borrow 1 of each ETH derivative
        pool.borrow(tokenListNew.cbETH, 1 ether, INTEREST_RATE_MODE, REFERAL_CODE, alice);
        pool.borrow(tokenListNew.weETH, 1 ether, INTEREST_RATE_MODE, REFERAL_CODE, alice);
        pool.borrow(tokenListNew.wstETH, 1 ether, INTEREST_RATE_MODE, REFERAL_CODE, alice);

        assertEq(IERC20(tokenListNew.weth).balanceOf(alice), wethBefore - supplyAmount);
        assertEq(IERC20(tokenListNew.wstETH).balanceOf(alice), wstETHBefore + 1 ether);
        assertEq(IERC20(tokenListNew.weETH).balanceOf(alice), weETHBefore + 1 ether);
        assertEq(IERC20(tokenListNew.cbETH).balanceOf(alice), cbETHBefore + 1 ether);

        vm.stopPrank();
    }

    function test_AAVE_AToken_BalanceOf() public {
        // supply 6 weth from alice
        uint256 supplyAmount = 6 ether;
        _supplyToPool(tokenListNew.weth, alice, supplyAmount);

        // check aWETH balance of alice
        (address aWETHAddress,,) = contracts.protocolDataProvider.getReserveTokensAddresses(tokenListNew.weth);
        IAToken aWETH = IAToken(aWETHAddress);
        assertEq(aWETH.balanceOf(alice), supplyAmount);
        // liquidity index is 1.000000000000000000 now
        assertEq(aWETH.scaledBalanceOf(alice), supplyAmount);
    }

    function test_AAVE_AToken_BearingInterest() public {
        uint256 startBalance = IERC20(tokenListNew.weth).balanceOf(alice);
        // supply 6 weth from alice
        uint256 supplyAmount = 6 ether;
        _supplyToPool(tokenListNew.weth, alice, supplyAmount);
        // check aWETH balance of alice
        (address aWETHAddress,,) = contracts.protocolDataProvider.getReserveTokensAddresses(tokenListNew.weth);
        IAToken aWETH = IAToken(aWETHAddress);

        // Pass some blocks to accumulate interest
        vm.roll(block.number + 1000);
        vm.warp(block.timestamp + 1000 * 12); // Assuming ~12 second blocks
        // Check balances have increased due to interest accrual
        assertGt(aWETH.balanceOf(alice), supplyAmount);

        // withdraw all aWETH from alice
        vm.prank(alice);
        pool.withdraw(tokenListNew.weth, type(uint256).max, alice);
        assertGt(IERC20(tokenListNew.weth).balanceOf(alice), startBalance);
    }

    function test_AAVE_LTV_Info() public {
        uint256 supplyAmount = 6 ether;
        _supplyToPool(tokenListNew.weth, alice, supplyAmount);

        vm.prank(alice);
        pool.setUserEMode(EModeCategory);

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(alice);

        uint256 baseCurrencyUnit = contracts.aaveOracle.BASE_CURRENCY_UNIT();
        uint256 availableBorrowsInBaseCurrency = totalCollateralBase.percentMul(ltv);
        uint256 ethPrice = contracts.aaveOracle.getAssetPrice(tokenListNew.weth);
        uint256 supplyAmountInBaseCurrency = supplyAmount / 1 ether * ethPrice;

        assertEq(totalCollateralBase, supplyAmountInBaseCurrency);
        assertEq(totalDebtBase, 0);
        assertEq(availableBorrowsBase, availableBorrowsInBaseCurrency);
        assertEq(currentLiquidationThreshold, 9300);
        assertEq(ltv, 9000);
        assertGt(healthFactor, 0);
    }

    function test_AAVE_borrow_maxLTV() public {
        uint256 supplyAmount = 6 ether;
        _supplyToPool(tokenListNew.weth, alice, supplyAmount);

        vm.prank(alice);
        pool.setUserEMode(EModeCategory);

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(alice);

        uint256 debtPrice = contracts.aaveOracle.getAssetPrice(tokenListNew.weth);
        uint256 maxBorrowAmount = (availableBorrowsBase * 1e8 / debtPrice) * 1 ether / 1e8;

        vm.prank(alice);
        pool.borrow(tokenListNew.weth, maxBorrowAmount, INTEREST_RATE_MODE, REFERAL_CODE, alice);

        (,, uint256 availableBorrowsBaseAfter,,,) = pool.getUserAccountData(alice);

        assertEq(availableBorrowsBaseAfter, 0);
    }
}
