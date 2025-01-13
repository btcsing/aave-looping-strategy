// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "lib/aave-v3-origin/src/contracts/extensions/v3-config-engine/AaveV3Payload.sol";
import {TestnetERC20} from "lib/aave-v3-origin/src/contracts/mocks/testnet-helpers/TestnetERC20.sol";
import {MockAggregator} from "lib/aave-v3-origin/src/contracts/mocks/oracle/CLAggregators/MockAggregator.sol";
import {ACLManager} from "lib/aave-v3-origin/src/contracts/protocol/configuration/ACLManager.sol";
import {MarketReport} from "lib/aave-v3-origin/src/deployments/interfaces/IMarketReportTypes.sol";

import {MainnetContracts} from "script/Contracts.sol";

/**
 * @dev Smart contract for token listing, for testing purposes
 * IMPORTANT Parameters are pseudo-random, DON'T USE THIS ANYHOW IN PRODUCTION
 * @author BGD Labs
 * @dev this is mimic the AaveV3TestListing.sol at "lib/aave-v3-origin/tests/mocks/AaveV3TestListing.sol";
 */
contract AaveV3ETHDerivativesTestListing is AaveV3Payload {
    bytes32 public constant POOL_ADMIN_ROLE_ID = 0x12ad05bde78c5ab75238ce885307f96ecd482bb402ef831f99e7018a0f169b7b;

    address public immutable WETH_ADDRESS;
    address public immutable WETH_MOCK_PRICE_FEED;

    address public immutable WEETH_ADDRESS;
    address public immutable WEETH_MOCK_PRICE_FEED;

    address public immutable WSTETH_ADDRESS;
    address public immutable WSTETH_MOCK_PRICE_FEED;

    address public immutable CBETH_ADDRESS;
    address public immutable CBETH_MOCK_PRICE_FEED;

    address immutable ATOKEN_IMPLEMENTATION;
    address immutable VARIABLE_DEBT_TOKEN_IMPLEMENTATION;

    ACLManager immutable ACL_MANAGER;

    constructor(IEngine customEngine, address weth9, MarketReport memory report) AaveV3Payload(customEngine) {
        // 2025-01-08 price, 1 WETH = 3364 USD, 1 WEETH = 3562 USD, 1 WSTETH = 4000 USD, 1 CBETH = 3664 USD
        WETH_ADDRESS = weth9;
        WETH_MOCK_PRICE_FEED = address(new MockAggregator(3364e8));

        WEETH_ADDRESS = MainnetContracts.WEETH;
        WEETH_MOCK_PRICE_FEED = address(new MockAggregator(3562e8));

        WSTETH_ADDRESS = MainnetContracts.WSTETH;
        WSTETH_MOCK_PRICE_FEED = address(new MockAggregator(4000e8));

        CBETH_ADDRESS = MainnetContracts.CBETH;
        CBETH_MOCK_PRICE_FEED = address(new MockAggregator(3664e8));

        ATOKEN_IMPLEMENTATION = report.aToken;
        VARIABLE_DEBT_TOKEN_IMPLEMENTATION = report.variableDebtToken;

        ACL_MANAGER = ACLManager(report.aclManager);
    }

    function newListingsCustom() public view override returns (IEngine.ListingWithCustomImpl[] memory) {
        IEngine.ListingWithCustomImpl[] memory listingsCustom = new IEngine.ListingWithCustomImpl[](4);

        IEngine.InterestRateInputData memory rateParams = IEngine.InterestRateInputData({
            optimalUsageRatio: 45_00,
            baseVariableBorrowRate: 0,
            variableRateSlope1: 4_00,
            variableRateSlope2: 60_00
        });

        listingsCustom[0] = IEngine.ListingWithCustomImpl(
            IEngine.Listing({
                asset: WETH_ADDRESS,
                assetSymbol: "WETH",
                priceFeed: WETH_MOCK_PRICE_FEED,
                rateStrategyParams: rateParams,
                enabledToBorrow: EngineFlags.ENABLED,
                borrowableInIsolation: EngineFlags.DISABLED,
                withSiloedBorrowing: EngineFlags.DISABLED,
                flashloanable: EngineFlags.ENABLED,
                ltv: 82_50,
                liqThreshold: 86_00,
                liqBonus: 5_00,
                reserveFactor: 10_00,
                supplyCap: 0,
                borrowCap: 0,
                debtCeiling: 0,
                liqProtocolFee: 10_00
            }),
            IEngine.TokenImplementations({aToken: ATOKEN_IMPLEMENTATION, vToken: VARIABLE_DEBT_TOKEN_IMPLEMENTATION})
        );

        listingsCustom[1] = IEngine.ListingWithCustomImpl(
            IEngine.Listing({
                asset: WEETH_ADDRESS,
                assetSymbol: "WEETH",
                priceFeed: WEETH_MOCK_PRICE_FEED,
                rateStrategyParams: rateParams,
                enabledToBorrow: EngineFlags.ENABLED,
                borrowableInIsolation: EngineFlags.DISABLED,
                withSiloedBorrowing: EngineFlags.DISABLED,
                flashloanable: EngineFlags.ENABLED,
                ltv: 82_50,
                liqThreshold: 86_00,
                liqBonus: 5_00,
                reserveFactor: 10_00,
                supplyCap: 0,
                borrowCap: 0,
                debtCeiling: 0,
                liqProtocolFee: 10_00
            }),
            IEngine.TokenImplementations({aToken: ATOKEN_IMPLEMENTATION, vToken: VARIABLE_DEBT_TOKEN_IMPLEMENTATION})
        );

        listingsCustom[2] = IEngine.ListingWithCustomImpl(
            IEngine.Listing({
                asset: WSTETH_ADDRESS,
                assetSymbol: "WSTETH",
                priceFeed: WSTETH_MOCK_PRICE_FEED,
                rateStrategyParams: rateParams,
                enabledToBorrow: EngineFlags.ENABLED,
                borrowableInIsolation: EngineFlags.DISABLED,
                withSiloedBorrowing: EngineFlags.DISABLED,
                flashloanable: EngineFlags.ENABLED,
                ltv: 82_50,
                liqThreshold: 86_00,
                liqBonus: 5_00,
                reserveFactor: 10_00,
                supplyCap: 0,
                borrowCap: 0,
                debtCeiling: 0,
                liqProtocolFee: 10_00
            }),
            IEngine.TokenImplementations({aToken: ATOKEN_IMPLEMENTATION, vToken: VARIABLE_DEBT_TOKEN_IMPLEMENTATION})
        );

        listingsCustom[3] = IEngine.ListingWithCustomImpl(
            IEngine.Listing({
                asset: CBETH_ADDRESS,
                assetSymbol: "CBETH",
                priceFeed: CBETH_MOCK_PRICE_FEED,
                rateStrategyParams: rateParams,
                enabledToBorrow: EngineFlags.ENABLED,
                borrowableInIsolation: EngineFlags.DISABLED,
                withSiloedBorrowing: EngineFlags.DISABLED,
                flashloanable: EngineFlags.ENABLED,
                ltv: 82_50,
                liqThreshold: 86_00,
                liqBonus: 5_00,
                reserveFactor: 10_00,
                supplyCap: 0,
                borrowCap: 0,
                debtCeiling: 0,
                liqProtocolFee: 10_00
            }),
            IEngine.TokenImplementations({aToken: ATOKEN_IMPLEMENTATION, vToken: VARIABLE_DEBT_TOKEN_IMPLEMENTATION})
        );

        return listingsCustom;
    }

    function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
        return IEngine.PoolContext({networkName: "Local", networkAbbreviation: "Loc"});
    }

    function _postExecute() internal override {
        ACL_MANAGER.renounceRole(POOL_ADMIN_ROLE_ID, address(this));
    }
}
