// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;
pragma abicoder v2;

import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {Factory} from "./Factory.sol";
import {IPool} from "./interfaces/IPool.sol";

/**
 * @title 
 * @author 
 * @notice 继承Factory后，用来创建池子、查询池子，createAndInitializePoolIfNecessary、getPool(token0,token1,index)、getAllPools
 * 第一部署该合约
 */
contract PoolManager is Factory, IPoolManager {
    Pair[] public pairs;

    // constructor() public {}
    // 之所以重新定义一个getPairs方法，而不用pairs变量自动生成的get方法，因为自动生成的get方法需要传index，这里需要返回整个pairs数组
    function getPairs() external view override returns (Pair[] memory) {
        return pairs;
    }

    // 获取所有交易对的所有pools
    function getAllPools() 
        external
        view
        override
        returns (PoolInfo[] memory poolsInfo)
    {
        uint32 length = 0;
        // 先算一下大小
        for (uint32 i = 0; i < pairs.length; i++) {
            // pools[pairs[i].token0][pairs[i].token1]得到的是该pair的多个pool
            length += uint32(pools[pairs[i].token0][pairs[i].token1].length);
        }

        // 再填充数据
        poolsInfo = new PoolInfo[](length);
        uint256 index;
        for (uint32 i = 0; i < pairs.length; i++) {
            // 一个pair对应的pools中装的是多个Pool合约实例
            //  mapping(address => mapping(address => address[])) public pools;pools中存的是Pool合约的地址
            address[] memory addresses = pools[pairs[i].token0][pairs[i].token1];
            for (uint32 j = 0; j < addresses.length; j++) {
                IPool pool = IPool(addresses[j]);
                poolsInfo[index] = PoolInfo({
                    pool: addresses[j],
                    token0: pool.token0(),
                    token1: pool.token1(),
                    index: j,
                    fee: pool.fee(),
                    feeProtocol: 0,
                    tickLower: pool.tickLower(),
                    tickUpper: pool.tickUpper(),
                    tick: pool.tick(),
                    sqrtPriceX96: pool.sqrtPriceX96(),
                    liquidity: pool.liquidity()
                });
                index++;
            }
        }
        return poolsInfo;
    }

    // 用来创建池子，创建的池子的主要逻辑在factory中的createPool中，新池子在factory中被加到pools中，这里主要初始化新池子的交易价格
    function createAndInitializePoolIfNecessary(
        CreateAndInitializeParams calldata params
    ) external payable override returns (address poolAddress) {
        require(
            params.token0 < params.token1,
            "token0 must be less than token1"
        );
        // 调用Factory的createPool方法，创建一个交易对的pool
        poolAddress = this.createPool(
            params.token0,
            params.token1,
            params.tickLower,
            params.tickUpper,
            params.fee
        );
        // 实例化上面创建的pool
        IPool pool = IPool(poolAddress);
        // 获取该pool在该交易对的pools中的排行
        uint256 index = pools[pool.token0()][pool.token1()].length;

        // 新创建的池子，没有初始化价格，需要初始化价格
        if (pool.sqrtPriceX96() == 0) {
            // 将pool的sqrtPriceX96设为传入的CreateAndInitializeParams中的sqrtPriceX96
            pool.initialize(params.sqrtPriceX96);

            if (index == 1) {
                // 如果index == 1，说明该交易对是第一次添加，需要记录
                pairs.push(
                    Pair({token0: pool.token0(), token1: pool.token1()})
                );
            }
        }
    }
}
