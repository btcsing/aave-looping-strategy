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
        uint256 depositAmount = 100 * 10 ** 18;
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 ether) return;

        console.log("depositAmount", depositAmount);
        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);
        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check that the vault received the tokens
        assertEq(weth.balanceOf(address(vault)), depositAmount, "AAVELoopingStrategy did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(weth.balanceOf(alice), INITIAL_BALANCE - depositAmount, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
    }
}
