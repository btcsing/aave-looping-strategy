// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, Math, SafeERC20} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {IPoolDataProvider} from "lib/aave-v3-origin/src/contracts/interfaces/IPoolDataProvider.sol";
import {IAaveOracle} from "lib/aave-v3-origin/src/contracts/interfaces/IAaveOracle.sol";
import {AaveLoopingLogic} from "./AaveLoopingLogic.sol";

/**
 * @title AaveLoopingStrategy
 * @author Yieldnest
 * @notice This contract is a strategy for Aave Looping. It is responsible for depositing and withdrawing assets from the
 * vault.
 */
contract AaveLoopingStrategy is Vault {
    using Math for uint256;

    /// @notice Role for aave dependency manager permissions
    bytes32 public constant AAVE_DEPENDENCY_MANAGER_ROLE = keccak256("AAVE_DEPENDENCY_MANAGER_ROLE");
    /// @notice Role for deposit manager permissions
    bytes32 public constant DEPOSIT_MANAGER_ROLE = keccak256("DEPOSIT_MANAGER_ROLE");

    /// @notice Emitted when an asset is withdrawn
    event WithdrawAsset(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        address asset,
        uint256 assets,
        uint256 shares
    );

    /// @notice Emitted when the sync deposit flag is set
    event SetSyncDeposit(bool syncDeposit);

    /// @notice Emitted when the sync withdraw flag is set
    event SetSyncWithdraw(bool syncWithdraw);

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
    function _getStrategyStorage() internal pure virtual returns (AaveLoopingLogic.StrategyStorage storage $) {
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

        AaveLoopingLogic.StrategyStorage storage strategyStorage = _getStrategyStorage();

        for (uint256 i = 0; i < assetListLength; i++) {
            AaveLoopingLogic.AavePair memory pair = strategyStorage.aavePairs[assetList[i]];
            uint256 underlyingBalance = IERC20(assetList[i]).balanceOf(address(this));
            // 1:1 = (aToken or debtToken):underlyingToken
            //  see: https://aave.com/docs/developers/smart-contracts/tokenization#undefined-atoken
            uint256 aBalance = pair.aToken.balanceOf(address(this));
            uint256 debtBalance = pair.varDebtToken.balanceOf(address(this));
            uint256 balance = underlyingBalance + aBalance - debtBalance;
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
        AaveLoopingLogic.addAsset(asset_, decimals_);
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

        AaveLoopingLogic.deposit(asset_, assets);
    }

    /**
     * @notice Withdraws a given amount of assets and burns the equivalent amount of shares from the owner.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = _withdrawAsset(asset(), assets, receiver, owner);
    }

    /**
     * @notice Withdraws assets and burns equivalent shares from the owner.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares burned.
     */
    function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        public
        virtual
        nonReentrant
        returns (uint256 shares)
    {
        shares = _withdrawAsset(asset_, assets, receiver, owner);
    }

    /**
     * @notice Internal function for withdraws assets and burns equivalent shares from the owner.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares burned.
     */
    function _withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        internal
        returns (uint256 shares)
    {
        if (paused()) {
            revert Paused();
        }
        uint256 maxAssets = maxWithdrawAsset(asset_, owner);
        if (assets > maxAssets) {
            revert ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        (shares,) = _convertToShares(asset_, assets, Math.Rounding.Ceil);
        _withdrawAsset(asset_, _msgSender(), receiver, owner, assets, shares);
    }

    /**
     * @notice Internal function to handle withdrawals for specific assets.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     */
    function _withdrawAsset(
        address asset_,
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal {
        if (!_getAssetStorage().assets[asset_].active) {
            revert AssetNotActive();
        }

        _subTotalAssets(_convertAssetToBase(asset_, assets));

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        AaveLoopingLogic.StrategyStorage storage strategyStorage = _getStrategyStorage();

        if (strategyStorage.syncWithdraw) {
            assets = AaveLoopingLogic.syncWithdraw(asset_, assets, totalSupply(), shares);
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by a given owner.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function maxWithdraw(address owner) public view override returns (uint256 maxAssets) {
        maxAssets = _maxWithdrawAsset(asset(), owner);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn for a specific asset by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function maxWithdrawAsset(address asset_, address owner) public view returns (uint256 maxAssets) {
        maxAssets = _maxWithdrawAsset(asset_, owner);
    }

    /**
     * @notice Internal function to get the maximum amount of assets that can be withdrawn by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function _maxWithdrawAsset(address asset_, address owner) internal view virtual returns (uint256 maxAssets) {
        if (paused() || !_getAssetStorage().assets[asset_].active) {
            return 0;
        }
        uint256 availableAssets = AaveLoopingLogic.availableAssets(asset_);

        maxAssets = previewRedeemAsset(asset_, balanceOf(owner));
        maxAssets = availableAssets < maxAssets ? availableAssets : maxAssets;
    }

    /**
     * @notice Redeems a given amount of shares and transfers the equivalent amount of assets to the receiver.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The equivalent amount of assets.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 assets)
    {
        assets = _redeemAsset(asset(), shares, receiver, owner);
    }

    /**
     * @notice Redeems shares and transfers equivalent assets to the receiver.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The equivalent amount of assets.
     */
    function redeemAsset(address asset_, uint256 shares, address receiver, address owner)
        public
        virtual
        nonReentrant
        returns (uint256 assets)
    {
        assets = _redeemAsset(asset_, shares, receiver, owner);
    }

    /**
     * @notice Internal function for redeems shares and transfers equivalent assets to the receiver.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The equivalent amount of assets.
     */
    function _redeemAsset(address asset_, uint256 shares, address receiver, address owner)
        internal
        returns (uint256 assets)
    {
        if (paused()) {
            revert Paused();
        }
        uint256 maxShares = maxRedeemAsset(asset_, owner);
        if (shares > maxShares) {
            revert ExceededMaxRedeem(owner, shares, maxShares);
        }
        assets = previewRedeemAsset(asset_, shares);
        _withdrawAsset(asset_, _msgSender(), receiver, owner, assets, shares);
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        maxShares = _maxRedeemAsset(asset(), owner);
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function maxRedeemAsset(address asset_, address owner) public view returns (uint256 maxShares) {
        maxShares = _maxRedeemAsset(asset_, owner);
    }

    /**
     * @notice Internal function to get the maximum amount of shares that can be redeemed by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function _maxRedeemAsset(address asset_, address owner) internal view virtual returns (uint256 maxShares) {
        if (paused() || !_getAssetStorage().assets[asset_].active) {
            return 0;
        }

        uint256 availableAssets = AaveLoopingLogic.availableAssets(asset_);

        maxShares = balanceOf(owner);

        maxShares = availableAssets < previewRedeemAsset(asset_, maxShares)
            ? previewWithdrawAsset(asset_, availableAssets)
            : maxShares;
    }

    /**
     * @notice Previews the amount of shares that would be received for a given amount of assets.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to deposit.
     * @return shares The equivalent amount of shares.
     */
    function previewWithdrawAsset(address asset_, uint256 assets) public view virtual returns (uint256 shares) {
        (shares,) = _convertToShares(asset_, assets, Math.Rounding.Ceil);
    }

    /**
     * @notice Previews the amount of assets that would be received for a given amount of shares.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @return assets The equivalent amount of assets.
     */
    function previewRedeemAsset(address asset_, uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset_, shares, Math.Rounding.Floor);
    }

    /**
     * @notice Sets the sync deposit flag.
     * @param syncDeposit The new value for the sync deposit flag.
     */
    function setSyncDeposit(bool syncDeposit) external onlyRole(DEPOSIT_MANAGER_ROLE) {
        AaveLoopingLogic.StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.syncDeposit = syncDeposit;

        emit SetSyncDeposit(syncDeposit);
    }

    /**
     * @notice Sets the sync withdraw flag.
     * @param syncWithdraw The new value for the sync withdraw flag.
     */
    function setSyncWithdraw(bool syncWithdraw) external onlyRole(DEPOSIT_MANAGER_ROLE) {
        AaveLoopingLogic.StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.syncWithdraw = syncWithdraw;

        emit SetSyncWithdraw(syncWithdraw);
    }

    /// @notice Set the Aave pool, pool provider, and oracle
    /// @param pool The address of the Aave pool
    /// @param poolDataProvider The address of the Aave pool data provider
    /// @param oracle The address of the oracle
    function setAave(address pool, address poolDataProvider, address oracle)
        external
        onlyRole(AAVE_DEPENDENCY_MANAGER_ROLE)
    {
        AaveLoopingLogic.setAave(pool, poolDataProvider, oracle);
        emit SetAave(pool, poolDataProvider, oracle);
    }

    /// @notice Enable eMode for the strategy
    /// @param categoryId The eMode category ID to enable
    function setEMode(uint8 categoryId) external onlyRole(AAVE_DEPENDENCY_MANAGER_ROLE) {
        AaveLoopingLogic.StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.aavePool.setUserEMode(categoryId);
        emit SetEMode(categoryId);
    }

    /// @notice Enable flash loan for the strategy
    /// @param enabled Whether the flash loan is enabled
    function setFlashLoanEnabled(bool enabled) external onlyRole(AAVE_DEPENDENCY_MANAGER_ROLE) {
        AaveLoopingLogic.StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.flashLoanEnabled = enabled;
        emit SetFlashLoanEnabled(enabled);
    }

    /**
     * @notice Returns the current sync deposit flag.
     * @return syncDeposit The sync deposit flag.
     */
    function getSyncDeposit() public view returns (bool syncDeposit) {
        return _getStrategyStorage().syncDeposit;
    }

    /**
     * @notice Returns the current sync withdraw flag.
     * @return syncWithdraw The sync withdraw flag.
     */
    function getSyncWithdraw() public view returns (bool syncWithdraw) {
        return _getStrategyStorage().syncWithdraw;
    }

    /**
     * @notice Retrieves the Aave pair for an asset.
     * @param asset_ The address of the asset.
     * @return aToken The address of the aToken.
     * @return varDebtToken The address of the variable debt token.
     */
    function getPair(address asset_) public view returns (address aToken, address varDebtToken) {
        AaveLoopingLogic.StrategyStorage storage strategyStorage = _getStrategyStorage();
        return
            (address(strategyStorage.aavePairs[asset_].aToken), address(strategyStorage.aavePairs[asset_].varDebtToken));
    }

    /**
     * @notice Retrieves the Aave oracle.
     * @return The address of the Aave oracle.
     */
    function getAaveOracle() public view returns (address) {
        AaveLoopingLogic.StrategyStorage storage strategyStorage = _getStrategyStorage();
        return address(strategyStorage.aaveOracle);
    }

    /**
     * @notice Gets the address of the AaveLoopingLogic library
     * @return The address of the AaveLoopingLogic library
     */
    function getAaveLoopingLogic() public pure returns (address) {
        return address(AaveLoopingLogic);
    }

    /// @notice Execute operation for the AAVE flash loan callback
    /// @param asset The address of the asset
    /// @param amount The amount of assets to flash loan
    /// @param premium The flash loan fee
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium, // flash loan fee
        address, // initiator
        bytes memory
    ) public returns (bool) {
        return AaveLoopingLogic.aaveFlashLoanCallback(asset, amount, premium);
    }
}
