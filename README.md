## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## NOTE

-   Interest rate mode only support 2 (VARIABLE) now, see [DataTypes.InterestRateMode](https://github.com/aave-dao/aave-v3-origin/blob/main/src/contracts/protocol/libraries/types/DataTypes.sol#L148)
-   AAVE Oracle is 8 decimals -> BASE_CURRENCY_UNIT is 1e8
    -   ex: eth output is 326882770019 , the price is 3268.82770019
    -   using [getAssetPrice](https://etherscan.io/address/0x54586bE62E3c3580375aE3723C145253060Ca0C2#readContract)() and play here https://etherscan.io/address/0x54586bE62E3c3580375aE3723C145253060Ca0C2#readContract

-   collateraBase, debtBase same as above
    -   totalCollateralBase = 326760657 -> 3267.60657
    -   totalDebtBase = 1222066 -> 122.2066
    -   play [getUserAccountData](https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2)() here https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
