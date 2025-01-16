// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";

import {SetupAaveLoopingStrategy} from "test/unit/helpers/SetupAaveLoopingStrategy.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

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

        // deal eth to MockUniswapV3Router
        deal(MC.WETH, MC.UNISWAPV3_SWAP_ROUTER, 100_000 ether);
        deal(MC.WEETH, MC.UNISWAPV3_SWAP_ROUTER, 100_000 ether);
    }

    function test_AaveLoopingStrategy_withdraw_sync_disable() public {
        uint256 withdrawAmount = 1 ether;
        withdrawAmount = uint256(bound(withdrawAmount, 1e8, 10_000 ether));
        assertEq(vault.getSyncDeposit(), false, "syncDeposit should be false");
        assertEq(vault.getSyncWithdraw(), false, "syncWithdraw should be false");

        uint256 beforeBalance = weth.balanceOf(alice);
        vm.prank(alice);
        // deposit
        vault.deposit(withdrawAmount, alice);
        assertEq(
            weth.balanceOf(alice), beforeBalance - withdrawAmount, "Alice did not subtract the correct amount of token"
        );
        // withdraw now
        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        assertEq(weth.balanceOf(alice), beforeBalance, "Alice did not receive the correct amount of token");
    }

    function test_AaveLoopingStrategy_sync_redeem_success(uint256 withdrawAmount) public {
        withdrawAmount = bound(withdrawAmount, 1e8, 10_000 ether);
        vm.startPrank(ADMIN);
        vault.setSyncDeposit(true);
        vault.setSyncWithdraw(true);
        vault.setFlashLoanEnabled(true);
        vm.stopPrank();

        vm.startPrank(alice);
        // deposit
        uint256 sharesMinted = vault.deposit(withdrawAmount, alice);
        // redeem
        uint256 totalAssets = vault.totalAssets();
        uint256 beforeRedeemBalance = weth.balanceOf(alice);
        vault.redeem(sharesMinted, alice, alice);
        // only alice deposit & withdraw, need get all totalAssets
        assertApproxEqAbs(
            weth.balanceOf(alice),
            beforeRedeemBalance + totalAssets,
            2,
            "Alice did not receive the correct redeem amount of token"
        );

        (address aToken, address varDebtToken) = vault.getPair(address(weth));

        // only accept  <= 2 wei, because rounding shift issue
        assertApproxEqAbs(IERC20(aToken).balanceOf(address(vault)), 0, 2, "aToken balance should be 0 after withdraw");
        assertApproxEqAbs(
            IERC20(varDebtToken).balanceOf(address(vault)), 0, 2, "debt token balance should be 0 after withdraw"
        );
        assertApproxEqAbs(weth.balanceOf(address(vault)), 0, 2, "weth balance should be 0 after withdraw");
        assertApproxEqAbs(vault.totalAssets(), 0, 2, "totalAssets should be 0 after withdraw");
        assertApproxEqAbs(vault.totalSupply(), 0, 2, "totalSupply should be 0 after withdraw");
        vm.stopPrank();
    }

    // function test_AaveLoopingStrategy_sync_withdraw_success() public {
    //     uint256 withdrawAmount = 1 ether;
    function test_AaveLoopingStrategy_sync_withdraw_success(uint256 withdrawAmount) public {
        withdrawAmount = bound(withdrawAmount, 1e8, 10_000 ether);

        // at least cover the deposit flash loan fee 0.05%, but 10x leverage, so using 0.5%
        uint256 depositAmount = withdrawAmount * 10050 / 10000;

        vm.startPrank(ADMIN);
        vault.setSyncDeposit(true);
        vault.setSyncWithdraw(true);
        vault.setFlashLoanEnabled(true);
        vm.stopPrank();

        vm.startPrank(alice);
        // deposit
        vault.deposit(depositAmount, alice);
        // withdraw
        uint256 beforeBalance = weth.balanceOf(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        assertApproxEqAbs(
            weth.balanceOf(alice),
            beforeBalance + withdrawAmount,
            2,
            "Alice withdraw did not receive the correct amount of token"
        );
        vm.stopPrank();
    }

    function test_AaveLoopingStrategy_sync_withdraw_borrow_other_asset_success(uint256 withdrawAmount) public {
        // function test_AaveLoopingStrategy_sync_withdraw_borrow_other_asset_success() public {
        // uint256 withdrawAmount = 1 ether;
        withdrawAmount = bound(withdrawAmount, 1e8, 10_000 ether);

        // at least cover the deposit & withdraw flash loan fee 0.05%, but 10x leverage, and swap fee, so using 2%
        uint256 depositAmount = withdrawAmount * 10200 / 10000;

        vm.startPrank(ADMIN);
        vault.setSyncDeposit(true);
        vault.setSyncWithdraw(true);
        vault.setFlashLoanEnabled(true);
        vault.addAsset(MC.WEETH, false);
        vault.setBorrowAsset(address(MC.WEETH));
        vm.stopPrank();

        vm.startPrank(alice);
        // deposit
        vault.deposit(depositAmount, alice);

        // withdraw
        uint256 beforeBalance = weth.balanceOf(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        vm.assertGt(weth.balanceOf(alice), beforeBalance, "Alice withdraw did not receive the correct amount of token");
        vm.assertGt(weth.balanceOf(alice), beforeBalance, "Alice withdraw did not receive the correct amount of token");
        vm.stopPrank();
    }

    function test_AaveLoopingLogic_linked_library() public {
        address logicAddr = vault.getAaveLoopingLogic();
        assertNotEq(logicAddr, address(0), "AaveLoopingLogic address should not be 0");
        assertNotEq(logicAddr, address(vault), "AaveLoopingLogic address should not be the current contract");

        // cannot call availableAssets() in AaveLoopingStrategy, function not exist, only exist in AaveLoopingLogic, following will get compile error
        // vault.availableAssets(address(weth));
        vm.expectRevert(bytes(""));
        logicAddr.call(abi.encodeWithSignature("availableAssets(address)", address(weth)));
    }
}
