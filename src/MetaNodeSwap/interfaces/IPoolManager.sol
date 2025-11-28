// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;
pragma abicoder v2;

import {IFactory} from "./IFactory.sol";

interface IPoolManager is IFactory {
    struct PoolInfo {
        address pool;
        address token0;
        address token1;
        uint32 index;
        uint24 fee;
        uint8 feeProtocol;
        int24 tickLower;
        int24 tickUpper;
        int24 tick;
        uint160 sqrtPriceX96;
        uint128 liquidity;
    }

    struct Pair {
        address token0;
        address token1;
    }

    function getPairs() external view returns (Pair[] memory);

    function getAllPools() external view returns (PoolInfo[] memory poolsInfo);

    struct CreateAndInitializeParams {
        address token0;
        address token1;
        uint24 fee; //500 = 0.05% (适用于稳定币对),3000 = 0.3% (适用于大多数交易对),10000 = 1.0% (适用于波动性大的代币对)
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
    }

    function createAndInitializePoolIfNecessary(
        CreateAndInitializeParams calldata params
    ) external payable returns (address pool);
}
