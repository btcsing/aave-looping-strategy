// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

// std imports
import {Test} from "lib/forge-std/src/Test.sol";
// yieldnest imports
import {TransparentUpgradeableProxy as TUProxy} from "lib/yieldnest-vault/src/Common.sol";
import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";
import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
// import {MockProvider} from "lib/yieldnest-vault/test/unit/mocks/MockProvider.sol";
import {MockRateProvider} from "test/unit/mocks/MockRateProvider.sol";
// local imports
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {AaveLoopingStrategy} from "src/AaveLoopingStrategy.sol";
import {EtchUtils} from "test/unit/helpers/EtchUtils.sol";
import {ETHRateProvider} from "src/module/ETHRateProvider.sol";
import {SetupAAVEPool} from "test/unit/helpers/aave/SetupAAVEPool.sol";
// import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
// import {IPoolDataProvider} from "lib/aave-v3-origin/src/contracts/interfaces/IPoolDataProvider.sol";

contract SetupAaveLoopingStrategy is Test, EtchUtils, MainnetActors {
    AaveLoopingStrategy public vault;
    // MockRateProvider public provider;
    ETHRateProvider public provider;

    WETH9 public weth;
    IERC20 public weeth;
    IERC20 public wsteth;
    IERC20 public cbeth;

    address public alice = address(0x0a11ce);
    address public bob = address(0x0b0b);
    address public chad = address(0x0cad);

    // AAVE pool
    address public aavePool;
    address public aavePoolDataProvider;
    address public aaveOracle;
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function deploy() public {
        // setup vault
        string memory name = "YieldNest AAVE Looping Strategy";
        string memory symbol = "ynAaveLooping";

        mockAll();
        aavePool = setupAAVE.getPool();
        aavePoolDataProvider = setupAAVE.getPoolDataProvider();
        aaveOracle = setupAAVE.getOracle();
        provider = new ETHRateProvider();
        AaveLoopingStrategy implementation = new AaveLoopingStrategy();
        // Deploy the proxy
        bytes memory initData =
            abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol, 18, 0, true, true);

        TUProxy vaultProxy = new TUProxy(address(implementation), ADMIN, initData);

        vault = AaveLoopingStrategy(payable(address(vaultProxy)));
        weth = WETH9(payable(MC.WETH));
        weeth = IERC20(MC.WEETH);
        wsteth = IERC20(MC.WSTETH);
        cbeth = IERC20(MC.CBETH);

        configureAaveLoopingStrategy();
    }

    function configureAaveLoopingStrategy() internal {
        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        vault.grantRole(vault.AAVE_DEPENDENCY_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.DEPOSIT_MANAGER_ROLE(), ADMIN);
        // set provider
        vault.setProvider(address(provider));

        // set AAVE pool
        vault.setAave(aavePool, aavePoolDataProvider, aaveOracle);
        vault.setEMode(setupAAVE.EModeCategory());

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
