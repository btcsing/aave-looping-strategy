# Aave Looping Strategy

## Motivation

- Implement a state of the art 4626 vault like using [Yieldnest](https://github.com/yieldnest/vault)
- Implement a lend looping strategy using AAVE
    - using ETH or ETH derivatives tokens

## Intro

- this repo enable Aave **EMode** for higher LTV, see [Aave EMode](https://aave.com/docs/developers/smart-contracts/pool-configurator#only-risk-or-pool-admins-methods-setemodecategory)
    - we only care ETH and ETH derivatives tokens, so we can enable EMode here
    - like in mainnet, EMode for ETH correlated tokens category can get 93% LTV (very higher!) from around 80% 

## Looping Strategy

### deposit method

this repo provide 2 looping strategy, loopingLoan() and flashLoan()

- loopingLoan():  it's a basic looping strategy, it will loop until user availableBorrowsBase is less than 0.01 USD
- flashLoan(): it's a flash loan strategy, it will borrow max amount and deposit it back to pool, idea can see  [looping](https://medium.com/contango-xyz/what-is-looping-78421c8a1367)

- using fuzzy test runing 260 times, the result as following:

| Strategy | Fee | Avg. Gas | Looping Times |
|----------|-----|----------|---------------|
| loopingLoan() | - | 21,405,789 | 121 (using 1 ether) |
| flashLoan() | 0.05% | 628,503 | 1 |

we can see flashLoan() can save huge gas (~97%) compared to loopingLoan(), but it need to pay 0.05% fee for flash loan

enable the flash loan feature
```
setFlashLoanEnabled(true);
```

### redeem & withdraw method

- because Aave has repayWithATokens() feature, so we can use it to repay debt and avoid flash loan again

## NOTE

-   Interest rate mode only support VARIABLE(2) debt now , see [DataTypes.InterestRateMode](https://github.com/aave-dao/aave-v3-origin/blob/main/src/contracts/protocol/libraries/types/DataTypes.sol#L148)

-   LTV percentage is 10,000 base, like 93% = 9300 
    -  using getEModeCategoryData (id=1) from https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2#readProxyContract

-   AAVE Oracle is 8 decimals -> BASE_CURRENCY_UNIT is 1e8
    -   ex: eth output is 326882770019 , the price is 3268.82770019 USD
    -   using [getAssetPrice](https://etherscan.io/address/0x54586bE62E3c3580375aE3723C145253060Ca0C2#readContract)() and play here https://etherscan.io/address/0x54586bE62E3c3580375aE3723C145253060Ca0C2#readContract

-   collateraBase, debtBase using above value, so
    -   totalCollateralBase = 326760657 -> 3267.60657 USD
    -   totalDebtBase = 1222066 -> 122.2066 USD
    -   play [getUserAccountData](https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2)() here https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2

-   edge case: if user deposit value too low (vaule less than 1e-8 USD), the totalCollateralBase still be 0, user still can not borrow anything
    -   ex: if user deposit 0.00000000000001 ETH, 10^-14 * 3364e8 = 0.000000000000003364 < 1e-8 USD, so the totalCollateralBase still be 0, user can not borrow anything even though user want borrow 10^-16 ETH!

-  contract size too large over 24kb, so we need to split it into 2 contracts, AaveLoopingStrategy and AaveLoopingLogic
   - see as following, contract size around ~27kb ( > 24kb) using optimizer with 200 runs, see using `forge build --size`
   

| Contract    | Runtime (B) | Initcode (B) | Runtime Margin |
|-------------|-------------|--------------|----------------|
| AaveLoopingStrategy | 27,226      | 27,453       | -2,650         |


   - we using [Linked Library](https://medium.com/coinmonks/all-you-should-know-about-libraries-in-solidity-dd8bc953eae7) to solve this problem,  let AaveLoopingLogic as a library which has public or external functions, and AaveLoopingStrategy delegate call it. AaveLoopingStrategy and AaveLoopingLogic are different address, so storage slot is different, so it's safe to use it.

   - after Linked Library, we can get contract size decrease from 27kb to 24kb, see as following

| Contract    | Runtime (B) | Initcode (B) | Runtime Margin |
|-------------|-------------|--------------|----------------|
| AaveLoopingStrategy | 23,934       | 24,161    | 642        |
| AaveLoopingLogic |5,677        | 5,730             | 18,899       |
