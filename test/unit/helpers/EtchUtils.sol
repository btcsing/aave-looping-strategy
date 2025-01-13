// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "lib/forge-std/src/mocks/MockERC20.sol";
import {SetupAAVEPool} from "./aave/SetupAAVEPool.sol";

contract EtchUtils is Test {
    SetupAAVEPool setupAAVE;

    function mockAll() public {
        mockWETH9();
        mockStETH();
        mockWEETH();
        mockWSTETH();
        mockCBETH();
        // mock AAVE pool and set to var pool
        mockAAVEPool();
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

    function mockWEETH() public {
        MockERC20 mockERC20 = new MockERC20();
        vm.etch(MainnetContracts.WEETH, address(mockERC20).code);
        MockERC20(MainnetContracts.WEETH).initialize("WEETH", "WEETH", 18);
    }

    function mockWSTETH() public {
        MockERC20 mockERC20 = new MockERC20();
        vm.etch(MainnetContracts.WSTETH, address(mockERC20).code);
        MockERC20(MainnetContracts.WSTETH).initialize("WSTETH", "WSTETH", 18);
    }

    function mockCBETH() public {
        MockERC20 mockERC20 = new MockERC20();
        vm.etch(MainnetContracts.CBETH, address(mockERC20).code);
        MockERC20(MainnetContracts.CBETH).initialize("CBETH", "CBETH", 18);
    }

    function mockAAVEPool() internal {
        setupAAVE = new SetupAAVEPool();
        setupAAVE.deploy();
    }

    // function mockProvider() public {
    //     Provider provider = new MockProvider();
    //     bytes memory code = address(provider).code;
    //     vm.etch(MainnetContracts.PROVIDER, code);
    // }
}
