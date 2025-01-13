# Aave Looping Strategy

## Motivation

- Implement a state of the art 4626 vault like using [Yieldnest](https://github.com/yieldnest/vault)
- Implement a lend looping strategy using AAVE
    - using ETH or ETH derivatives tokens

## Intro

- this repo enable Aave **EMode** for higher LTV, see [Aave EMode](https://aave.com/docs/developers/smart-contracts/pool-configurator#only-risk-or-pool-admins-methods-setemodecategory)
    - we only care ETH and ETH derivatives tokens, so we enable EMode here
    - like in mainnet, EMode for ETH correlated tokens category can get 93% LTV (very higher!) from around 80% 

## Looping Strategy

this repo provide 2 looping strategy, loopingLoan() and flashLoan()

- loopingLoan():  it's a basic looping strategy, it will loop until user availableBorrowsBase is less than 0.01 USD
- flashLoan(): it's a flash loan strategy, it will borrow max amount and deposit it back to pool, idea can see  [looping](https://medium.com/contango-xyz/what-is-looping-78421c8a1367)

- using fuzzy test runing 260 times, the result as following:

| Strategy | Fee | Avg. Gas | Looping Times |
|----------|-----|----------|---------------|
| loopingLoan() | - | 21,405,789 | 121 (using 1 ether) |
| flashLoan() | 0.05% | 628,503 | 1 |

we can see flashLoan() can save huge gas (~97%) compared to loopingLoan(), but it need to pay 0.05% fee for flash loan


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
