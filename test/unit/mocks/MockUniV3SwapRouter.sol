// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";

contract MockUniswapV3Router is ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        amountOut = params.amountOutMinimum;
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);
        return amountOut;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        amountIn = params.amountInMaximum;
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(params.tokenOut).transfer(params.recipient, params.amountOut);
        return amountIn;
    }
}
