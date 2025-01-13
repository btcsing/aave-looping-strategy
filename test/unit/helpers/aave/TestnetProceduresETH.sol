    // SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "lib/aave-v3-origin/src/deployments/interfaces/IMarketReportTypes.sol";
import {TestnetProcedures} from "lib/aave-v3-origin/tests/utils/TestnetProcedures.sol";
import {WETH9} from "lib/aave-v3-origin/src/contracts/dependencies/weth/WETH9.sol";
import {TestnetERC20} from "lib/aave-v3-origin/src/contracts/mocks/testnet-helpers/TestnetERC20.sol";
import {AaveV3ETHDerivativesTestListing} from "./AaveV3ETHDerivativesTestListing.sol";
import {ACLManager} from "lib/aave-v3-origin/src/contracts/protocol/configuration/ACLManager.sol";
import {
    AaveV3ConfigEngine,
    IAaveV3ConfigEngine
} from "lib/aave-v3-origin/src/contracts/extensions/v3-config-engine/AaveV3ConfigEngine.sol";
import {MarketReportUtils} from "lib/aave-v3-origin/src/deployments/contracts/utilities/MarketReportUtils.sol";

import {MainnetContracts} from "script/Contracts.sol";

contract TestnetProceduresETH is TestnetProcedures {
    using MarketReportUtils for MarketReport;

    struct TokenListNew {
        address weth;
        address weETH;
        address wstETH;
        address cbETH;
    }

    TokenListNew public tokenListNew;

    function getPool() public view returns (address) {
        return report.poolProxy;
    }

    function getPoolDataProvider() public view returns (address) {
        return address(contracts.protocolDataProvider);
    }

    function getOracle() public view returns (address) {
        return address(contracts.aaveOracle);
    }

    function initTestEnvironmentNew() public {
        _initTestEnvironmentNew(false);
    }

    // mimic the deployAaveV3TestnetAssets function
    function _initTestEnvironmentNew(bool l2) internal {
        poolAdmin = makeAddr("POOL_ADMIN");

        alicePrivateKey = 0xA11CE;
        bobPrivateKey = 0xB0B;
        carolPrivateKey = 0xCA801;

        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);
        carol = vm.addr(carolPrivateKey);

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");

        (
            Roles memory roles,
            MarketConfig memory config,
            DeployFlags memory flags,
            MarketReport memory deployedContracts
        ) = _getMarketInput(poolAdmin);
        roleList = roles;
        flags.l2 = l2;

        // Etch the create2 factory
        vm.etch(
            0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7,
            hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"
        );

        (report, tokenListNew) = deployAaveV3TestnetAssetsNew(poolAdmin, roles, config, flags, deployedContracts);

        contracts = report.toContractsReport();

        weth = WETH9(payable(tokenListNew.weth));

        vm.label(tokenListNew.weth, "WETH");
        vm.label(tokenListNew.weETH, "weETH");
        vm.label(tokenListNew.wstETH, "wstETH");
        vm.label(tokenListNew.cbETH, "cbETH");
    }

    function deployAaveV3TestnetAssetsNew(
        address deployer,
        Roles memory roles,
        MarketConfig memory config,
        DeployFlags memory flags,
        MarketReport memory deployedContracts
    ) internal returns (MarketReport memory, TokenListNew memory) {
        TokenListNew memory assetsList;

        assetsList.weth = MainnetContracts.WETH;
        config.wrappedNativeToken = assetsList.weth;
        MarketReport memory r = deployAaveV3Testnet(deployer, roles, config, flags, deployedContracts);

        AaveV3ETHDerivativesTestListing testnetListingPayload =
            new AaveV3ETHDerivativesTestListing(IAaveV3ConfigEngine(r.configEngine), assetsList.weth, r);

        // Add additional assets
        assetsList.weETH = testnetListingPayload.WEETH_ADDRESS();
        assetsList.wstETH = testnetListingPayload.WSTETH_ADDRESS();
        assetsList.cbETH = testnetListingPayload.CBETH_ADDRESS();

        testnetListingPayload.newListingsCustom();

        ACLManager manager = ACLManager(r.aclManager);

        vm.prank(roles.poolAdmin);
        manager.addPoolAdmin(address(testnetListingPayload));

        testnetListingPayload.execute();

        return (r, assetsList);
    }
}
