// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";

import {SetupAaveLoopingStrategy} from "test/unit/helpers/SetupAaveLoopingStrategy.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";

import {console} from "lib/forge-std/src/console.sol";

contract AaveLoopingStrategyWithdrawUnitTest is SetupAaveLoopingStrategy {
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

    function test_AaveLoopingStrategy_withdraw_sync_disable() public {
        uint256 withdrawalAmount = 1 ether;
        withdrawalAmount = uint256(bound(withdrawalAmount, 1e8, 10_000 ether));
        assertEq(vault.getSyncDeposit(), false, "syncDeposit should be false");
        assertEq(vault.getSyncWithdraw(), false, "syncWithdraw should be false");

        uint256 beforeBalance = weth.balanceOf(alice);
        vm.prank(alice);
        // deposit
        vault.deposit(withdrawalAmount, alice);
        assertEq(
            weth.balanceOf(alice),
            beforeBalance - withdrawalAmount,
            "Alice did not subtract the correct amount of token"
        );
        // withdraw now
        vm.prank(alice);
        vault.withdraw(withdrawalAmount, alice, alice);

        assertEq(weth.balanceOf(alice), beforeBalance, "Alice did not receive the correct amount of token");
    }

    function test_AaveLoopingStrategy_withdraw_sync_revert_ExceededMaxWithdraw() public {
        uint256 withdrawalAmount = 1 ether;
        withdrawalAmount = bound(withdrawalAmount, 1e8, 10_000 ether);

        vm.startPrank(ADMIN);
        vault.setSyncDeposit(true);
        vault.setSyncWithdraw(true);
        vault.setFlashLoanEnabled(true);
        vm.stopPrank();

        uint256 beforeBalance = weth.balanceOf(alice);
        vm.startPrank(alice);
        // deposit
        vault.deposit(withdrawalAmount, alice);
        // withdraw
        // because after using flash loan, the balance need subtracted the flash loan fee
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.ExceededMaxWithdraw.selector, alice, withdrawalAmount, vault.maxWithdraw(alice)
            )
        );
        vault.withdraw(withdrawalAmount, alice, alice);
        vm.stopPrank();
    }

    function test_AaveLoopingStrategy_withdraw_sync_redeem_success() public {
        uint256 withdrawalAmount = 1 ether;
        withdrawalAmount = bound(withdrawalAmount, 1e8, 10_000 ether);

        vm.startPrank(ADMIN);
        vault.setSyncDeposit(true);
        vault.setSyncWithdraw(true);
        vault.setFlashLoanEnabled(true);
        vm.stopPrank();

        uint256 beforeBalance = weth.balanceOf(alice);
        vm.startPrank(alice);
        // deposit
        vault.deposit(withdrawalAmount, alice);
        // withdraw
        // because after using flash loan, the balance need subtracted the flash loan fee
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.ExceededMaxWithdraw.selector, alice, withdrawalAmount, vault.maxWithdraw(alice)
            )
        );
        vault.withdraw(withdrawalAmount, alice, alice);
        vm.stopPrank();
    }
}
