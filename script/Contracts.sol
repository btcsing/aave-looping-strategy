// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

library MainnetContracts {
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;

    address public constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant WOETH = 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    // address public constant YNETHX = 0x657d9ABA1DBb59e53f9F3eCAA878447dCfC96dCb;
    // address public constant YNETH = 0x09db87A538BD693E9d08544577d5cCfAA6373A48;
    // address public constant YNLSDE = 0x35Ec69A77B79c255e5d47D5A3BdbEFEfE342630c;

    // address public constant SWELL = 0xf951E335afb289353dc249e82926178EaC7DEd78;

    address public constant CL_STETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address public constant TIMELOCK = 0xb5b52c63067E490982874B0d0F559668Bbe0c36B;
    address public constant FACTORY = 0x1756987c66eC529be59D3Ec1edFB005a2F9728E1;
    address public constant PROXY_ADMIN = 0xA02A8DC24171aC161cCb74Ef02C28e3cA2204783;

    address public constant PROVIDER = address(123456789); // TODO: Update with deployed Provider
    address public constant BUFFER = address(987654321); // TODO: Update with deployed buffer
}
