// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, Math, SafeERC20} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {IPoolDataProvider} from "lib/aave-v3-origin/src/contracts/interfaces/IPoolDataProvider.sol";
import {DataTypes} from "lib/aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {console} from "lib/forge-std/src/console.sol";

/**
 * @title AAVELoopingStrategy
 * @author Yieldnest
 * @notice This contract is a strategy for AAVE Looping. It is responsible for depositing and withdrawing assets from the
 * vault.
 */
contract AAVELoopingStrategy is Vault {
    /// @notice Role for aave dependency manager permissions
    bytes32 public constant AAVE_DEPENDENCY_MANAGER_ROLE = keccak256("AAVE_DEPENDENCY_MANAGER_ROLE");
    /// @notice  only support InterestRateMode.VARIABLE now, see code DataTypes.sol
    uint256 public constant INTEREST_RATE_MODE = uint256(DataTypes.InterestRateMode.VARIABLE);
    /// @notice  only support 0 now
    uint16 public constant REFERAL_CODE = 0;

    struct AAVEPair {
        IERC20 aToken;
        IERC20 varDebtToken;
    }

    /// @notice Storage structure for strategy-specific parameters
    struct StrategyStorage {
        /// @notice AAVE pool
        IPool pool;
        /// @notice AAVE pool provider
        IPoolDataProvider poolDataProvider;
        /// @notice Mapping of asset to AAVE pair
        /// @dev underlying token map to the corresponding aToken and debtToken
        mapping(address => AAVEPair) aavePairs;
    }

    /// @notice Emitted when the AAVE pool & poolDataProvider is set
    event SetAAVE(address pool, address poolDataProvider);

    /**
     * @notice Retrieves the strategy storage structure.
     * @return $ The strategy storage structure.
     */
    function _getStrategyStorage() internal pure virtual returns (StrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy")
            $.slot := 0x0ef3e973c65e9ac117f6f10039e07687b1619898ed66fe088b0fab5f5dc83d88
        }
    }

    /**
     * @notice Computes the total assets of the vault.
     * @return totalBaseBalance The total balance of the vault in the base asset.
     */
    function _computeTotalAssets() internal view override returns (uint256 totalBaseBalance) {
        console.log("inin computeTotalAssets");
        console.log(" if (_getVaultStorage().alwaysComputeTotalAssets) {:", _getVaultStorage().alwaysComputeTotalAssets);
        VaultStorage memory vaultStorage = _getVaultStorage();

        // Assumes native asset has same decimals as asset() (the base asset)
        totalBaseBalance = vaultStorage.countNativeAsset ? address(this).balance : 0;

        AssetStorage storage assetStorage = _getAssetStorage();
        address[] memory assetList = assetStorage.list;
        uint256 assetListLength = assetList.length;

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        for (uint256 i = 0; i < assetListLength; i++) {
            AAVEPair memory pair = strategyStorage.aavePairs[assetList[i]];
            // 1:1 = (aToken or debtToken):underlyingToken
            //  see: https://aave.com/docs/developers/smart-contracts/tokenization#undefined-atoken
            uint256 aBalance = pair.aToken.balanceOf(address(this));
            uint256 debtBalance = pair.varDebtToken.balanceOf(address(this));
            uint256 balance = aBalance - debtBalance;
            console.log("aBalance", aBalance);
            console.log("debtBalance", debtBalance);
            console.log("balance", balance);
            if (balance == 0) continue;
            totalBaseBalance += _convertAssetToBase(assetList[i], balance);
        }
    }

    /**
     * @notice Adds a new asset to the vault.
     * @param asset_ The address of the asset.
     * @param decimals_ The decimals of the asset.
     * @param active_ Whether the asset is active or not.
     */
    function _addAsset(address asset_, uint8 decimals_, bool active_) internal override {
        super._addAsset(asset_, decimals_, active_);
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        (address aToken,, address variableDebtToken) =
            strategyStorage.poolDataProvider.getReserveTokensAddresses(asset_);
        if (aToken == address(0) || variableDebtToken == address(0)) revert ZeroAddress();
        strategyStorage.aavePairs[asset_] = AAVEPair(IERC20(aToken), IERC20(variableDebtToken));
    }

    /**
     * @notice Internal function to handle deposits.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     * @param baseAssets The base asset conversion of shares.
     */
    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    ) internal override {
        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        IERC20(asset_).approve(address(strategyStorage.pool), assets);
        strategyStorage.pool.deposit(asset_, assets, address(this), 0);
    }

    /// @notice Set the AAVE pool and pool provider
    /// @param _pool The address of the AAVE pool
    /// @param _poolDataProvider The address of the AAVE pool data provider
    function setAAVE(address _pool, address _poolDataProvider) external onlyRole(AAVE_DEPENDENCY_MANAGER_ROLE) {
        if (_pool == address(0) || _poolDataProvider == address(0)) revert ZeroAddress();

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.pool = IPool(_pool);
        strategyStorage.poolDataProvider = IPoolDataProvider(_poolDataProvider);

        emit SetAAVE(_pool, _poolDataProvider);
    }

    /// @notice Enable eMode for the strategy
    /// @param categoryId The eMode category ID to enable
    function enableEMode(uint8 categoryId) external onlyRole(AAVE_DEPENDENCY_MANAGER_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.pool.setUserEMode(categoryId);
        emit EnableEMode(categoryId);
    }

    /// @notice Emitted when eMode is enabled
    /// @param categoryId The eMode category ID that was enabled
    event EnableEMode(uint8 categoryId);

    /**
     * @notice Retrieves the AAVE pair for an asset.
     * @param asset_ The address of the asset.
     * @return aToken The address of the aToken.
     * @return varDebtToken The address of the variable debt token.
     */
    function getPair(address asset_) public view returns (address aToken, address varDebtToken) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        return
            (address(strategyStorage.aavePairs[asset_].aToken), address(strategyStorage.aavePairs[asset_].varDebtToken));
    }
}
