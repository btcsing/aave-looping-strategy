// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

// std imports
import {Test} from "lib/forge-std/src/Test.sol";
// yieldnest imports
import {TransparentUpgradeableProxy as TUProxy} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";
import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
// import {MockProvider} from "lib/yieldnest-vault/test/unit/mocks/MockProvider.sol";
import {MockRateProvider} from "test/unit/mocks/MockRateProvider.sol";
// local imports
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {AAVELoopingStrategy} from "src/AAVELoopingStrategy.sol";
import {EtchUtils} from "test/unit/helpers/EtchUtils.sol";
import {ETHRateProvider} from "src/module/ETHRateProvider.sol";

contract SetupAAVELoopingStrategy is Test, EtchUtils, MainnetActors {
    AAVELoopingStrategy public vault;
    // MockRateProvider public provider;
    ETHRateProvider public provider;

    WETH9 public weth;

    address public alice = address(0x0a11ce);
    address public bob = address(0x0b0b);
    address public chad = address(0x0cad);

    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function deploy() public {
        string memory name = "YieldNest AAVE Looping Strategy";
        string memory symbol = "ynAaveLooping";

        mockAll();
        provider = new ETHRateProvider();
        AAVELoopingStrategy implementation = new AAVELoopingStrategy();
        // Deploy the proxy
        bytes memory initData =
            abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol, 18, 0, true, false);

        TUProxy vaultProxy = new TUProxy(address(implementation), ADMIN, initData);

        vault = AAVELoopingStrategy(payable(address(vaultProxy)));
        weth = WETH9(payable(MC.WETH));

        configureAAVELoopingStrategy();
    }

    function configureAAVELoopingStrategy() internal {
        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        // set provider
        vault.setProvider(address(provider));

        // set has allocator
        // vault.setHasAllocator(true);

        // by default, we don't sync deposits or withdraws
        // we set it for individual tests
        // vault.setSyncDeposit(true);
        // vault.setSyncWithdraw(true);

        // add assets
        vault.addAsset(MC.WETH, true);

        // by default, we don't set any rules

        vault.unpause();

        vm.stopPrank();

        vault.processAccounting();
    }
}
