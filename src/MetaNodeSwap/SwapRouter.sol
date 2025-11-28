// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;
pragma abicoder v2;

// import {IERC20} from "../meme/IERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {console} from "forge-std/console.sol";

/**
 * @title 
 * @author 
 * @notice 调用pool合约的swap方法，用来交易、询价
 * 第三部署该合约
 */
contract SwapRouter is ISwapRouter {
    IPoolManager public poolManager;

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @dev Parses a revert reason that should contain the numeric quote
    function parseRevertReason(
        bytes memory reason
    ) private pure returns (int256, int256) {
        if (reason.length != 64) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (int256, int256)); //从swapCallback的revert中解析询价结果
    }

    // SwapRouter调用pool合约的swap方法执行交易
    function swapInPool(
        IPool pool,
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        try // 询价时调用到swapCallback回调函数时，会revert，这里就try catch来保证代码的正常执行
            pool.swap(
                recipient,
                zeroForOne,
                amountSpecified,
                sqrtPriceLimitX96,
                data
            )
        returns (int256 _amount0, int256 _amount1) { // 正常交易完pool.swap方法返回两种币的数量
            return (_amount0, _amount1);
        } catch (bytes memory reason) { // 询价时revert，处理异常，parseRevertReason中将swapCallback中encode的数据decode，得到的就是询价结果
            return parseRevertReason(reason);
        }
    }

    // 当用户输入的是要花掉的token数量时调用此方法
    function exactInput(
        ExactInputParams calldata params
    ) external payable override returns (uint256 amountOut) {
        // 记录确定的输入 token 的 amount，即pool合约中swap方法的amountSpecified参数，即要花掉的token数量
        uint256 amountIn = params.amountIn;

        // 根据 tokenIn 和 tokenOut 的大小关系，确定是从 token0 到 token1 还是从 token1 到 token0
        // 如果tokenIn小于tokenOut，就是用tokenIn买tokenOut，如果tokenIn大于tokenOut，就是用tokenOut买tokenIn
        bool zeroForOne = params.tokenIn < params.tokenOut;
        // 遍历指定的每一个 pool
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            // 调用Factory中的getPool方法，获取交易对，getPool时会对tokenIn和tokenOut排序来保证获取pool时tokenIn和tokenOut中较小的那个地址在前面
            address poolAddress = poolManager.getPool(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i]
            );
            console.log("SwapRouter.exactInput.poolAddress: ", poolAddress);
            // 如果 pool 不存在，则抛出错误
            require(poolAddress != address(0), "Pool not found");

            // 获取 pool 实例
            IPool pool = IPool(poolAddress);

            // 构造 swapCallback 函数需要的参数
            bytes memory data = abi.encode(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i],
                params.recipient == address(0) ? address(0) : msg.sender
            );

            // 调用 pool 的 swap 函数，进行交换，并拿到返回的 token0 和 token1 的数量
            (int256 amount0, int256 amount1) = this.swapInPool(
                pool,
                params.recipient,
                zeroForOne,
                int256(amountIn),
                params.sqrtPriceLimitX96,
                data
            );

            // 更新 amountIn 和 amountOut，in输入的要花掉的token，out是计算出的能买到的token数量
            amountIn -= uint256(zeroForOne ? amount0 : amount1);
            amountOut += uint256(zeroForOne ? -amount1 : -amount0);

            // 如果 amountIn 为 0，表示交换完成，跳出循环
            if (amountIn == 0) {
                break;
            }
        }
        console.log("SwapRouter.exactInput.amountOut: ", amountOut);
        // 固定数量的amountIn来交换不固定数量的amountOut
        // 如果交换到的 amountOut 小于指定的最少数量 amountOutMinimum，则抛出错误，回滚交易
        require(amountOut >= params.amountOutMinimum, "Slippage exceeded");

        // 发送 Swap 事件
        emit Swap(msg.sender, zeroForOne, params.amountIn, amountIn, amountOut);

        // 返回 amountOut
        return amountOut;
    }

    // 当用户输入的是要买的token数量时调用此方法
    function exactOutput(
        ExactOutputParams calldata params
    ) external payable override returns (uint256 amountIn) {
        // 记录确定的输出 token 的 amount
        uint256 amountOut = params.amountOut;

        // 根据 tokenIn 和 tokenOut 的大小关系，确定是从 token0 到 token1 还是从 token1 到 token0
        bool zeroForOne = params.tokenIn < params.tokenOut;

        // 遍历指定的每一个 pool
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddress = poolManager.getPool(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i]
            );

            // 如果 pool 不存在，则抛出错误
            require(poolAddress != address(0), "Pool not found");

            // 获取 pool 实例
            IPool pool = IPool(poolAddress);

            // 构造 swapCallback 函数需要的参数
            bytes memory data = abi.encode(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i],
                params.recipient == address(0) ? address(0) : msg.sender
            );

            // 调用 pool 的 swap 函数，进行交换，并拿到返回的 token0 和 token1 的数量
            (int256 amount0, int256 amount1) = this.swapInPool(
                pool,
                params.recipient,
                zeroForOne,
                -int256(amountOut), //将要买的token数量设为负值
                params.sqrtPriceLimitX96,
                data
            );

            // 更新 amountOut 和 amountIn，out是要买的token数量，in是计算出的要花的token数量
            amountOut -= uint256(zeroForOne ? -amount1 : -amount0);
            amountIn += uint256(zeroForOne ? amount0 : amount1);

            // 如果 amountOut 为 0，表示交换完成，跳出循环，如果amountOut不为0，说明当前pool不满足要买到的币的数量，再从下一个pool中继续兑换
            if (amountOut == 0) {
                break;
            }
        }
        console.log("SwapRouter.exactOutput.amountIn: ", amountIn);
        console.log("SwapRouter.exactOutput.params.amountInMaximum: ", params.amountInMaximum);
        console.log("SwapRouter.exactOutput.amountIn <= params.amountInMaximum: ", amountIn <= params.amountInMaximum);
        // 固定数量的amountOut，来计算要花多少amountIn
        // 如果交换到指定数量 tokenOut 消耗的 tokenIn 数量超过指定的最大值，报错，回滚交易
        require(amountIn <= params.amountInMaximum, "Slippage exceeded");

        // 发射 Swap 事件
        emit Swap(
            msg.sender,
            zeroForOne,
            params.amountOut,
            amountOut,
            amountIn
        );

        // 返回交换后的 amountIn
        return amountIn;
    }

    // 询价报价，指定 tokenIn 的数量和 tokenOut 的最小值，返回 tokenOut 的实际数量
    // 我要买，我最多出tokenIn个币，我最少想买到tokenOut个币，返回的实际tokenOut要比我期望的多才行
    function quoteExactInput(
        QuoteExactInputParams calldata params
    ) external override returns (uint256 amountOut) {
        // 因为没有实际 approve，所以这里交易会报错，我们捕获错误信息，解析需要多少 token

        return
            this.exactInput(
                ExactInputParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    indexPath: params.indexPath,
                    recipient: address(0),
                    deadline: block.timestamp + 1 hours,
                    amountIn: params.amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            );
    }

    // 询价报价，指定 tokenOut 的数量和 tokenIn 的最大值，返回 tokenIn 的实际数量
    // 我要买tokenOut个币，最多能出tokenIn个币，返回的实际tokenIn要比我期望的少才行
    function quoteExactOutput(
        QuoteExactOutputParams calldata params
    ) external override returns (uint256 amountIn) {
        return
            this.exactOutput(
                ExactOutputParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    indexPath: params.indexPath,
                    recipient: address(0),
                    deadline: block.timestamp + 1 hours,
                    amountOut: params.amountOut,
                    amountInMaximum: type(uint256).max,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            );
    }

    // 调用Pool合约的swap方法时回调此方法，用于将用户支付的代币转给池子
    function swapCallback(
        int256 amount0Delta, // 要花的token数量
        int256 amount1Delta, // 买到的token的数量
        bytes calldata data
    ) external override {
        // transfer token
        (address tokenIn, address tokenOut, uint32 index, address payer) = abi
            .decode(data, (address, address, uint32, address));
        address _pool = poolManager.getPool(tokenIn, tokenOut, index);

        // 检查 callback 的合约地址是否是 Pool
        require(_pool == msg.sender, "Invalid callback caller");

        uint256 amountToPay = amount0Delta > 0
            ? uint256(amount0Delta)
            : uint256(amount1Delta);
        // payer 是 address(0)，这是一个用于预估 token 的请求（quoteExactInput or quoteExactOutput）
        // 参考代码 https://github.com/Uniswap/v3-periphery/blob/main/contracts/lens/Quoter.sol#L38
        // 当调用quoteExactInput 或 quoteExactOutput询价时，quoteExactInput 或 quoteExactOutput内部也会调用exactInput或exactOutput，从而调用pool合约的swap方法，
        // 但是此时的recipient是address(0)，从而会走下面这段代码，只获取到要花多少或能买多少，后边到交易时revert，这样就不会真正进行交易，然后在上面的swapInPool方法中try catch
        if (payer == address(0)) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amount0Delta)
                mstore(add(ptr, 0x20), amount1Delta)
                revert(ptr, 64) //将询价结果塞入ptr
            }
        }

        // 正常交易，转账给交易池
        if (amountToPay > 0) {
            bool success = IERC20(tokenIn).transferFrom(payer, _pool, amountToPay);
            if(!success) {
                revert("tokenIn transfer failed");
            }
        }
    }
}
