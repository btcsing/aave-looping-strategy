// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, Math, SafeERC20} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {IPoolDataProvider} from "lib/aave-v3-origin/src/contracts/interfaces/IPoolDataProvider.sol";
import {IAaveOracle} from "lib/aave-v3-origin/src/contracts/interfaces/IAaveOracle.sol";
import {DataTypes} from "lib/aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {console} from "lib/forge-std/src/console.sol";

/**
 * @title AaveLoopingStrategy
 * @author Yieldnest
 * @notice This contract is a strategy for Aave Looping. It is responsible for depositing and withdrawing assets from the
 * vault.
 */
contract AaveLoopingStrategy is Vault {
    /// @notice Role for aave dependency manager permissions
    bytes32 public constant AAVE_DEPENDENCY_MANAGER_ROLE = keccak256("AAVE_DEPENDENCY_MANAGER_ROLE");
    /// @notice  aave only support InterestRateMode.VARIABLE now, see code DataTypes.sol
    uint256 public constant INTEREST_RATE_MODE = uint256(DataTypes.InterestRateMode.VARIABLE);
    /// @notice  referal code
    uint16 public constant REFERAL_CODE = 0;

    /// @notice  aave pair struct, aToken and variable debt token
    struct AavePair {
        IERC20 aToken;
        IERC20 varDebtToken;
    }

    /// @notice Storage structure for strategy-specific parameters
    struct StrategyStorage {
        /// @notice Aave pool
        IPool aavePool;
        /// @notice Aave pool provider
        IPoolDataProvider aavePoolDataProvider;
        /// @notice Mapping of asset to Aave pair
        /// @dev underlying token map to the corresponding aToken and debtToken
        mapping(address => AavePair) aavePairs;
        /// @notice Aave Oracle address
        IAaveOracle aaveOracle;
        /// @notice Whether the flash loan is enabled
        bool flashLoanEnabled;
    }

    /// @notice Emitted when the Aave pool & poolDataProvider is set
    event SetAave(address pool, address poolDataProvider, address oracle);

    /// @notice Emitted when AAVE eMode and which categoryId is set
    /// @param categoryId The AAVE eMode category ID that was enabled
    event SetEMode(uint8 categoryId);

    /// @notice Emitted when AAVE flash loan is enabled
    /// @param enabled Whether the flash loan is enabled
    event SetFlashLoanEnabled(bool enabled);

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
        VaultStorage memory vaultStorage = _getVaultStorage();

        // Assumes native asset has same decimals as asset() (the base asset)
        totalBaseBalance = vaultStorage.countNativeAsset ? address(this).balance : 0;

        AssetStorage storage assetStorage = _getAssetStorage();
        address[] memory assetList = assetStorage.list;
        uint256 assetListLength = assetList.length;

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        for (uint256 i = 0; i < assetListLength; i++) {
            AavePair memory pair = strategyStorage.aavePairs[assetList[i]];
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
            strategyStorage.aavePoolDataProvider.getReserveTokensAddresses(asset_);
        if (aToken == address(0) || variableDebtToken == address(0)) revert ZeroAddress();
        strategyStorage.aavePairs[asset_] = AavePair(IERC20(aToken), IERC20(variableDebtToken));
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
        IERC20(asset_).approve(address(strategyStorage.aavePool), type(uint256).max);
        strategyStorage.aavePool.deposit(asset_, assets, address(this), REFERAL_CODE);

        // availableBorrowsBase's BASE_CURRENCY_UNIT is 8 -> decimals is 8 (aaveOrcale)
        (,, uint256 availableBorrowsBase,,,) = strategyStorage.aavePool.getUserAccountData(address(this));
        uint8 times = 0;
        while (availableBorrowsBase > 0) {
            // debtPrice's BASE_CURRENCY_UNIT is 8 -> decimals is 8 (aaveOracle)
            uint256 debtPrice = strategyStorage.aaveOracle.getAssetPrice(asset_);
            uint256 maxBorrowAmount = (availableBorrowsBase * 1e8 / debtPrice) * 1 ether / 1e8;
            // borrow & deposit
            strategyStorage.aavePool.borrow(asset_, maxBorrowAmount, INTEREST_RATE_MODE, REFERAL_CODE, address(this));
            strategyStorage.aavePool.deposit(asset_, maxBorrowAmount, address(this), REFERAL_CODE);
            // check available borrows
            (,, availableBorrowsBase,,,) = strategyStorage.aavePool.getUserAccountData(address(this));
            console.log("availableBorrowsBase: ", availableBorrowsBase);
            times = times + 1;
            console.log("times: ", times);
            // 1e6 / 1e8 = 0.01 USD
            // (1e6 / debtPrice) -> around 0.000003030303 ETH, if debtPrice(ETH) is 3400*1e8 (3400 USD)
            if (availableBorrowsBase < 1e6) break;
        }

        IERC20(asset_).approve(address(strategyStorage.aavePool), 0);
    }

    /// @notice Set the Aave pool, pool provider, and oracle
    /// @param pool The address of the Aave pool
    /// @param poolDataProvider The address of the Aave pool data provider
    /// @param oracle The address of the oracle
    function setAave(address pool, address poolDataProvider, address oracle)
        external
        onlyRole(AAVE_DEPENDENCY_MANAGER_ROLE)
    {
        if (pool == address(0) || poolDataProvider == address(0) || oracle == address(0)) revert ZeroAddress();

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.aavePool = IPool(pool);
        strategyStorage.aavePoolDataProvider = IPoolDataProvider(poolDataProvider);
        strategyStorage.aaveOracle = IAaveOracle(oracle);

        emit SetAave(pool, poolDataProvider, oracle);
    }

    /// @notice Enable eMode for the strategy
    /// @param categoryId The eMode category ID to enable
    function setEMode(uint8 categoryId) external onlyRole(AAVE_DEPENDENCY_MANAGER_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.aavePool.setUserEMode(categoryId);
        emit SetEMode(categoryId);
    }

    /// @notice Enable flash loan for the strategy
    /// @param enabled Whether the flash loan is enabled
    function setFlashLoanEnabled(bool enabled) external onlyRole(AAVE_DEPENDENCY_MANAGER_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.flashLoanEnabled = enabled;
        emit SetFlashLoanEnabled(enabled);
    }

    /**
     * @notice Retrieves the Aave pair for an asset.
     * @param asset_ The address of the asset.
     * @return aToken The address of the aToken.
     * @return varDebtToken The address of the variable debt token.
     */
    function getPair(address asset_) public view returns (address aToken, address varDebtToken) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        return
            (address(strategyStorage.aavePairs[asset_].aToken), address(strategyStorage.aavePairs[asset_].varDebtToken));
    }

    function getAaveOracle() public view returns (address) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        return address(strategyStorage.aaveOracle);
    }
}
