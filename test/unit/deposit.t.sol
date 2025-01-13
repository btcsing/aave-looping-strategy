// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";

import {SetupAaveLoopingStrategy} from "test/unit/helpers/SetupAaveLoopingStrategy.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";

contract AaveLoopingStrategyDepositUnitTest is SetupAaveLoopingStrategy {
    function setUp() public {
        deploy();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_AaveLoopingStrategy_deposit_success(uint256 depositAmount) public {
        depositAmount = uint256(bound(depositAmount, 1e8, 10_000 ether));
        assertEq(vault.getSyncDeposit(), false, "syncDeposit should be false");
        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);
        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check that Alice's token balance decreased
        assertEq(weth.balanceOf(alice), INITIAL_BALANCE - depositAmount, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
    }

    function test_AaveLoopingStrategy_loopingLoan(uint256 depositAmount) public {
        // input value at least 1e-8 USD, 1e8 wei eth >= 1e-8 USD if eth price >= 100 USD (1e-10 eth *100 USD)
        depositAmount = uint256(bound(depositAmount, 1e8, 10_000 ether));

        vm.prank(ADMIN);
        vault.setSyncDeposit(true);

        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        (,,,,, uint256 healthFactor) = IPool(aavePool).getUserAccountData(address(vault));
        // healthFactor is scaled by 1e18
        assertGe(healthFactor, 1.03e18, "Health factor too low");
        // Check Vault should all used for deposit
        assertEq(weth.balanceOf(address(vault)), 0, "weth balance should be 0");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets
        // ltv = 9000 (90%) = 1/(1-0.9) = 10
        uint256 flashLoanFee = vault.totalAssets() * 10 * vault.FLASH_LOAN_FEE() / 10000;
        assertGt(vault.totalAssets(), depositAmount - flashLoanFee, "Total assets is not correctly");
    }

    function test_AaveLoopingStrategy_flashLoan(uint256 depositAmount) public {
        // input value at least 1e-8 USD, 1e8 wei eth >= 1e-8 USD if eth price >= 100 USD (1e-10 eth *100 USD)
        depositAmount = uint256(bound(depositAmount, 1e8, 10_000 ether));

        vm.startPrank(ADMIN);
        vault.setSyncDeposit(true);
        vault.setFlashLoanEnabled(true);
        vm.stopPrank();

        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        (,,,,, uint256 healthFactor) = IPool(aavePool).getUserAccountData(address(vault));

        // healthFactor is scaled by 1e18
        assertGe(healthFactor, 1.03e18, "Health factor too low");
        // Check Vault should all used for deposit
        assertEq(weth.balanceOf(address(vault)), 0, "weth balance should be 0");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets
        // ltv = 9000 (90%) = 1/(1-0.9) = 10
        uint256 flashLoanFee = vault.totalAssets() * 10 * vault.FLASH_LOAN_FEE() / 10000;
        assertGt(vault.totalAssets(), depositAmount - flashLoanFee, "Total assets is not correctly");
    }

    function test_AaveLoopingStrategy_interest_accrued() public {
        uint256 depositAmount = 2 ether;
        depositAmount = bound(depositAmount, 10, 100_000 ether);

        vm.prank(ADMIN);
        vault.setSyncDeposit(true);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssets = vault.totalAssets();
        uint256 sharesMinted = vault.previewDeposit(depositAmount);

        // Pass some blocks to accumulate interest
        vm.roll(block.number + 1000);
        vm.warp(block.timestamp + 1000 * 12); // Assuming ~12 second blocks

        // (address aToken, address varDebtToken) = vault.getPair(address(weth));
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 sharesMintedAfter = vault.previewDeposit(depositAmount);

        assertNotEq(totalAssets, totalAssetsAfter, "Total assets should be different");
        assertNotEq(sharesMinted, sharesMintedAfter, "Shares minted should be different");
    }
}
