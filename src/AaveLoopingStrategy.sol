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
    using Math for uint256;

    /// @notice Role for aave dependency manager permissions
    bytes32 public constant AAVE_DEPENDENCY_MANAGER_ROLE = keccak256("AAVE_DEPENDENCY_MANAGER_ROLE");
    /// @notice Role for deposit manager permissions
    bytes32 public constant DEPOSIT_MANAGER_ROLE = keccak256("DEPOSIT_MANAGER_ROLE");
    /// @notice  aave only support InterestRateMode.VARIABLE now, see code DataTypes.sol
    uint256 public constant INTEREST_RATE_MODE = uint256(DataTypes.InterestRateMode.VARIABLE);
    /// @notice  referal code
    uint16 public constant REFERAL_CODE = 0;
    /// @notice Aave V3 loan fee = 0.5%,
    /// @dev following ltv base, like 93% = 9300, 0.05% = 5, using getEModeCategoryData (id=1) from https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2#readProxyContract
    uint256 public constant FLASH_LOAN_FEE = 5;
    /// @notice smallest value to deposit, 1e8 wei eth, at least 1e-8 USD see README.md
    uint256 public constant DEPOSIT_SMALLEST_VALUE = 1e8;
    /// @notice ltv shift, 200 = 2%
    uint256 public constant LTV_SHIFT = 200;
    /// @notice flash loan mode transient slot, false for deposit, true for withdraw
    /// @dev keccak256("AAVELOOPING_FLASHLOAN_MODE_SLOT")
    bytes32 public constant FLASHLOAN_MODE_SLOT = 0x2b3b14fe842881695532b9b6ef96e6eccd0e90097912b05a542163e376929feb;

    /// @notice  aave pair struct for mapping underlying token to aToken and variable debt token
    struct AavePair {
        /// @notice aToken
        IERC20 aToken;
        /// @notice variable debt token
        IERC20 varDebtToken;
    }

    /// @notice Storage structure for strategy-specific parameters
    struct StrategyStorage {
        /// @notice Whether to sync deposit
        bool syncDeposit;
        /// @notice Whether to sync withdraw
        bool syncWithdraw;
        /// @notice Aave pool
        IPool aavePool;
        /// @notice Aave pool data provider
        IPoolDataProvider aavePoolDataProvider;
        /// @notice Mapping of asset to Aave pair
        /// @dev underlying token map to the corresponding aToken and debtToken
        mapping(address => AavePair) aavePairs;
        /// @notice Aave Oracle address
        IAaveOracle aaveOracle;
        /// @notice Whether the flash loan is enabled
        bool flashLoanEnabled;
    }

    /// @notice error when deposit value is too small
    error DepositTooSmall();

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
        if (assets < DEPOSIT_SMALLEST_VALUE) revert DepositTooSmall();
        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        if (strategyStorage.syncDeposit) {
            if (strategyStorage.flashLoanEnabled) {
                setFlashLoanMode(false);
                flashLoan(strategyStorage.aavePool, asset_, assets);
            } else {
                loopingLoan(strategyStorage.aavePool, strategyStorage.aaveOracle, asset_, assets);
            }
        }
    }

    /// @notice Flash loan for the strategy
    /// @param pool The address of the Aave pool
    /// @param asset_ The address of the asset
    /// @param assets The amount of assets to flash loan
    function flashLoan(IPool pool, address asset_, uint256 assets) internal {
        (,,,, uint256 ltv,) = pool.getUserAccountData(address(this));
        if (ltv == 0) {
            IERC20(asset_).approve(address(pool), assets);
            pool.deposit(asset_, assets, address(this), REFERAL_CODE);
            (,,,, ltv,) = pool.getUserAccountData(address(this));
        }

        // A: assets, F: flashLoan assets, ltv: loan to value (0.9), 0.5%: flash loan fee
        // 0.9 * (A + F) >= F * 1.0005
        // F <= A * 0.9 / (1.0005 - 0.9) -> F <= A * 0.9 / 0.1005  = A * 8.955
        uint256 targetLtv = ltv - 200;
        uint256 flashLoanAmount = assets.mulDiv(targetLtv, 1e4 + FLASH_LOAN_FEE - targetLtv, Math.Rounding.Floor);
        pool.flashLoanSimple(address(this), asset_, flashLoanAmount, "", REFERAL_CODE);
    }

    /// @notice Flash loan for the strategy
    /// @param pool The address of the Aave pool
    /// @param asset_ The address of the asset
    /// @param shares The amount of shares to flash loan
    function flashLoanWithdraw(IPool pool, address asset_, uint256 shares) internal {
        (,,,, uint256 ltv,) = pool.getUserAccountData(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        AavePair memory pair = strategyStorage.aavePairs[asset_];
        uint256 debt = pair.varDebtToken.balanceOf(address(this));
        uint256 debtAfterShares = debt.mulDiv(shares, totalSupply(), Math.Rounding.Floor);
        // true for withdraw
        setFlashLoanMode(true);
        pool.flashLoanSimple(address(this), asset_, debtAfterShares, "", REFERAL_CODE);
    }

    /// @notice Looping loan for the strategy
    /// @param pool The address of the Aave pool
    /// @param poolOracle The address of the Aave pool oracle
    /// @param asset_ The address of the asset
    /// @param assets The amount of assets to flash loan
    function loopingLoan(IPool pool, IAaveOracle poolOracle, address asset_, uint256 assets) internal {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        IERC20(asset_).approve(address(pool), type(uint256).max);
        pool.deposit(asset_, assets, address(this), REFERAL_CODE);

        // availableBorrowsBase's BASE_CURRENCY_UNIT is 8 -> decimals is 8 (aaveOrcale)
        (,, uint256 availableBorrowsBase,,,) = pool.getUserAccountData(address(this));
        while (availableBorrowsBase > 0) {
            // debtPrice's BASE_CURRENCY_UNIT is 8 -> decimals is 8 (aaveOracle)
            uint256 debtPrice = poolOracle.getAssetPrice(asset_);
            // uint256 maxBorrowAmount =  (availableBorrowsBase * 1e8 / debtPrice) * 1 ether / 1e8;
            uint256 maxBorrowAmount = availableBorrowsBase.mulDiv(1 ether, debtPrice, Math.Rounding.Floor);
            maxBorrowAmount = maxBorrowAmount.mulDiv(1e4 - LTV_SHIFT, 1e4, Math.Rounding.Floor);
            // borrow & deposit
            pool.borrow(asset_, maxBorrowAmount, INTEREST_RATE_MODE, REFERAL_CODE, address(this));
            pool.deposit(asset_, maxBorrowAmount, address(this), REFERAL_CODE);
            // check available borrows
            (,, availableBorrowsBase,,,) = pool.getUserAccountData(address(this));
            // 1e6 / 1e8 = 0.01 USD
            // (1e6 / debtPrice) -> around 0.000003030303 ETH, if debtPrice(ETH) is 3400*1e8 (3400 USD)
            if (availableBorrowsBase < 1e6) break;
        }

        IERC20(asset_).approve(address(pool), 0);
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
        console.log(" withdraw finish");
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
        console.log("maxAssets: ", maxAssets);
        console.log("assets: ", assets);
        if (assets > maxAssets) {
            console.log("in _withdrawAsset ExceededMaxWithdraw");
            revert ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        console.log("after ExceededMaxWithdraw");
        (shares,) = _convertToShares(asset_, assets, Math.Rounding.Ceil);
        console.log("after convertToShares");
        _withdrawAsset(asset_, _msgSender(), receiver, owner, assets, shares);
        console.log("after _withdrawAsset");
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

        uint256 vaultBalance = IERC20(asset_).balanceOf(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        if (strategyStorage.syncWithdraw) {
            require(strategyStorage.flashLoanEnabled, "flashLoan not enabled");
            setFlashLoanMode(false);
            flashLoanWithdraw(strategyStorage.aavePool, asset_, shares);
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
        uint256 availableAssets = _availableAssets(asset_);

        maxAssets = previewRedeemAsset(asset_, balanceOf(owner));

        maxAssets = availableAssets < maxAssets ? availableAssets : maxAssets;
    }

    /**
     * @notice Internal function to get the available amount of assets.
     * @param asset_ The address of the asset.
     * @return availableAssets The available amount of assets.
     */
    function _availableAssets(address asset_) internal view virtual returns (uint256 availableAssets) {
        availableAssets = IERC20(asset_).balanceOf(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        if (strategyStorage.syncWithdraw) {
            AavePair memory pair = strategyStorage.aavePairs[asset_];
            uint256 aBalance = pair.aToken.balanceOf(address(this));
            uint256 debtBalance = pair.varDebtToken.balanceOf(address(this));
            availableAssets = availableAssets + aBalance - debtBalance;
        }
    }

    /**
     * @notice Previews the amount of assets that would be received for a given amount of shares.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @return assets The equivalent amount of assets.
     */
    function previewRedeemAsset(address asset_, uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset_, shares, Math.Rounding.Floor);
        // assets = assets - _feeOnTotal(assets);
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        AavePair memory pair = strategyStorage.aavePairs[asset_];
        uint256 debtBalance = pair.varDebtToken.balanceOf(address(this));
        assets = assets - debtBalance.mulDiv(FLASH_LOAN_FEE, 1e4, Math.Rounding.Floor);
    }

    /**
     * @notice Sets the sync deposit flag.
     * @param syncDeposit The new value for the sync deposit flag.
     */
    function setSyncDeposit(bool syncDeposit) external onlyRole(DEPOSIT_MANAGER_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.syncDeposit = syncDeposit;

        emit SetSyncDeposit(syncDeposit);
    }

    /**
     * @notice Sets the sync withdraw flag.
     * @param syncWithdraw The new value for the sync withdraw flag.
     */
    function setSyncWithdraw(bool syncWithdraw) external onlyRole(DEPOSIT_MANAGER_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
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
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        return
            (address(strategyStorage.aavePairs[asset_].aToken), address(strategyStorage.aavePairs[asset_].varDebtToken));
    }

    /**
     * @notice Retrieves the Aave oracle.
     * @return The address of the Aave oracle.
     */
    function getAaveOracle() public view returns (address) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        return address(strategyStorage.aaveOracle);
    }

    /// @notice Get the flash loan mode from transient storage
    /// @return mode The flash loan mode (false for deposit, true for withdraw)
    function getFlashLoanMode() internal view returns (bool mode) {
        assembly {
            mode := tload(FLASHLOAN_MODE_SLOT)
        }
    }

    /// @notice Set the flash loan mode in transient storage
    /// @param mode The flash loan mode to set (false for deposit, true for withdraw)
    function setFlashLoanMode(bool mode) internal {
        assembly {
            tstore(FLASHLOAN_MODE_SLOT, mode)
        }
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
        bytes memory // params
    ) public returns (bool) {
        // console.log("in executeOperation:");
        if (getFlashLoanMode()) {
            // withdraw
            console.log("in flashloan withdraw");
        } else {
            StrategyStorage storage strategyStorage = _getStrategyStorage();
            require(msg.sender == address(strategyStorage.aavePool), "only aave pool");
            uint256 balance = IERC20(asset).balanceOf(address(this));
            uint256 debtAmount = amount + premium;
            // approve blance for deposit(), debtAmount for flashLoan's borrow+fee
            IERC20(asset).approve(address(strategyStorage.aavePool), balance + debtAmount);

            strategyStorage.aavePool.deposit(asset, balance, address(this), REFERAL_CODE);

            strategyStorage.aavePool.borrow(asset, debtAmount, INTEREST_RATE_MODE, REFERAL_CODE, address(this));
            return true;
        }
    }
}
