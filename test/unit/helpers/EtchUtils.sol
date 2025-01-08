// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";

contract EtchUtils is Test {
    function mockAll() public {
        mockWETH9();
        mockStETH();
        // mockProvider();
    }

    function mockWETH9() public {
        WETH9 weth = new WETH9();
        bytes memory code = address(weth).code;
        vm.etch(MainnetContracts.WETH, code);
    }

    function mockStETH() public {
        MockSTETH steth = new MockSTETH();
        bytes memory code = address(steth).code;
        vm.etch(MainnetContracts.STETH, code);
    }

    // function mockProvider() public {
    //     Provider provider = new MockProvider();
    //     bytes memory code = address(provider).code;
    //     vm.etch(MainnetContracts.PROVIDER, code);
    // }
}
