// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";

import {SetupAAVELoopingStrategy} from "test/unit/helpers/SetupAAVELoopingStrategy.sol";
import {console} from "lib/forge-std/src/console.sol";

contract AAVELoopingStrategyDepositUnitTest is SetupAAVELoopingStrategy {
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

    function test_AVELoopingStrategy_deposit_success() public {
        uint256 depositAmount = 2 ether;
        depositAmount = bound(depositAmount, 10, 100_000 ether);
        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);
        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        (address aToken, address varDebtToken) = vault.getPair(address(weth));

        // Check that the vault received the tokens
        assertGe(IERC20(aToken).balanceOf(address(vault)), depositAmount, "AAVELoopingStrategy did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(weth.balanceOf(alice), INITIAL_BALANCE - depositAmount, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
    }

    function test_AAVELoopingStrategy_interest_accrued() public {
        uint256 depositAmount = 2 ether;
        depositAmount = bound(depositAmount, 10, 100_000 ether);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssets = vault.totalAssets();
        uint256 sharesMinted = vault.previewDeposit(depositAmount);

        console.log("before totalAssets", totalAssets);
        console.log("before sharesMinted", sharesMinted);

        // Pass some blocks to accumulate interest
        vm.roll(block.number + 1000);
        vm.warp(block.timestamp + 1000 * 12); // Assuming ~12 second blocks

        // (address aToken, address varDebtToken) = vault.getPair(address(weth));
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 sharesMintedAfter = vault.previewDeposit(depositAmount);

        console.log("after totalAssets", totalAssetsAfter);
        console.log("after sharesMinted", sharesMintedAfter);

        assertNotEq(totalAssets, totalAssetsAfter, "Total assets should be different");
        assertNotEq(sharesMinted, sharesMintedAfter, "Shares minted should be different");
    }
}
