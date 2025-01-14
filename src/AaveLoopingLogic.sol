// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, Math, SafeERC20} from "lib/yieldnest-vault/src/Common.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {IPoolDataProvider} from "lib/aave-v3-origin/src/contracts/interfaces/IPoolDataProvider.sol";
import {IAaveOracle} from "lib/aave-v3-origin/src/contracts/interfaces/IAaveOracle.sol";
import {DataTypes} from "lib/aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title AaveLoopingStrategy
 * @author Yieldnest
 * @notice This contract is a strategy for Aave Looping. It is responsible for depositing and withdrawing assets from the
 * vault.
 */
library AaveLoopingLogic {
    using Math for uint256;

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
    /// @notice error when only aave pool can set flash loan mode
    error OnlyAavePool();

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
    function _getStrategyStorage() internal pure returns (StrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy")
            $.slot := 0x0ef3e973c65e9ac117f6f10039e07687b1619898ed66fe088b0fab5f5dc83d88
        }
    }

    /// @notice Flash loan for the strategy
    /// @param pool The address of the Aave pool
    /// @param asset_ The address of the asset
    /// @param assets The amount of assets to flash loan
    function flashLoan(IPool pool, address asset_, uint256 assets) public {
        (,,,, uint256 ltv,) = pool.getUserAccountData(address(this));
        if (ltv == 0) {
            IERC20(asset_).approve(address(pool), assets);
            pool.deposit(asset_, assets, address(this), REFERAL_CODE);
            (,,,, ltv,) = pool.getUserAccountData(address(this));
        }

        // A: assets, F: flashLoan assets, ltv: loan to value (0.9), 0.5%: flash loan fee
        // 0.9 * (A + F) >= F * 1.0005
        // F <= A * 0.9 / (1.0005 - 0.9) -> F <= A * 0.9 / 0.1005  = A * 8.955
        uint256 targetLtv = ltv - LTV_SHIFT;
        uint256 flashLoanAmount = assets.mulDiv(targetLtv, 1e4 + FLASH_LOAN_FEE - targetLtv, Math.Rounding.Floor);
        pool.flashLoanSimple(address(this), asset_, flashLoanAmount, "", REFERAL_CODE);
    }

    /// @notice Looping loan for the strategy
    /// @param pool The address of the Aave pool
    /// @param poolOracle The address of the Aave pool oracle
    /// @param asset_ The address of the asset
    /// @param assets The amount of assets to flash loan
    function loopingLoan(IPool pool, IAaveOracle poolOracle, address asset_, uint256 assets) public {
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
     * @notice Adds a new asset to the vault.
     * @param asset_ The address of the asset.
     * @param decimals_ The decimals of the asset.
     */
    function addAsset(address asset_, uint8 decimals_) external {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        (address aToken,, address variableDebtToken) =
            strategyStorage.aavePoolDataProvider.getReserveTokensAddresses(asset_);
        if (aToken == address(0) || variableDebtToken == address(0)) revert IVault.ZeroAddress();
        strategyStorage.aavePairs[asset_] = AavePair(IERC20(aToken), IERC20(variableDebtToken));
    }

    function deposit(address asset_, uint256 assets) external {
        if (assets < DEPOSIT_SMALLEST_VALUE) revert DepositTooSmall();
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        if (strategyStorage.syncDeposit) {
            if (strategyStorage.flashLoanEnabled) {
                flashLoan(strategyStorage.aavePool, asset_, assets);
            } else {
                loopingLoan(strategyStorage.aavePool, strategyStorage.aaveOracle, asset_, assets);
            }
        }
    }

    function syncWithdraw(address asset_, uint256 asset, uint256 totalSupply, uint256 shares)
        external
        returns (uint256 assets)
    {
        StrategyStorage storage strategyStorage = _getStrategyStorage();

        if (strategyStorage.syncWithdraw) {
            AavePair memory pair = strategyStorage.aavePairs[asset_];
            uint256 aToken = pair.aToken.balanceOf(address(this));
            // NOTE: subtract 1 wei to avoid rounding issue
            uint256 aTokenAfterShares = aToken.mulDiv(shares, totalSupply, Math.Rounding.Floor) - 1;
            uint256 debt = pair.varDebtToken.balanceOf(address(this));
            uint256 debtAfterShares = debt.mulDiv(shares, totalSupply, Math.Rounding.Floor);

            strategyStorage.aavePool.repayWithATokens(asset_, debtAfterShares, INTEREST_RATE_MODE);
            assets = aTokenAfterShares - debtAfterShares;
            strategyStorage.aavePool.withdraw(asset_, assets, address(this));
        }
    }

    function availableAssets(address asset_) external view returns (uint256 availableAssets) {
        availableAssets = IERC20(asset_).balanceOf(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        if (strategyStorage.syncWithdraw) {
            AavePair memory pair = strategyStorage.aavePairs[asset_];
            uint256 aBalance = pair.aToken.balanceOf(address(this));
            uint256 debtBalance = pair.varDebtToken.balanceOf(address(this));
            availableAssets = availableAssets + aBalance - debtBalance;
        }
    }

    /// @notice Execute operation for the AAVE flash loan callback
    /// @param asset The address of the asset
    /// @param amount The amount of assets to flash loan
    /// @param premium The flash loan fee
    function aaveFlashLoanCallback(
        address asset,
        uint256 amount,
        uint256 premium // flash loan fee
    ) external returns (bool) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        if (msg.sender != address(strategyStorage.aavePool)) revert OnlyAavePool();

        uint256 balance = IERC20(asset).balanceOf(address(this));
        uint256 debtAmount = amount + premium;
        // approve blance for deposit() & debtAmount for flashLoan's borrow+fee
        IERC20(asset).approve(address(strategyStorage.aavePool), balance + debtAmount);
        strategyStorage.aavePool.deposit(asset, balance, address(this), 0);
        strategyStorage.aavePool.borrow(asset, debtAmount, INTEREST_RATE_MODE, 0, address(this));

        return true;
    }

    /// @notice Set the Aave pool, pool provider, and oracle
    /// @param pool The address of the Aave pool
    /// @param poolDataProvider The address of the Aave pool data provider
    /// @param oracle The address of the oracle
    function setAave(address pool, address poolDataProvider, address oracle) external {
        if (pool == address(0) || poolDataProvider == address(0) || oracle == address(0)) revert IVault.ZeroAddress();

        AaveLoopingLogic.StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.aavePool = IPool(pool);
        strategyStorage.aavePoolDataProvider = IPoolDataProvider(poolDataProvider);
        strategyStorage.aaveOracle = IAaveOracle(oracle);
    }
}
