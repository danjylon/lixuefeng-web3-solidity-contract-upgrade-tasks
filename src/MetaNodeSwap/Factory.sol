// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {IFactory} from "./interfaces/IFactory.sol";
import {Pool} from "./Pool.sol";
import {IPool} from "./interfaces/IPool.sol";

/**
 * @title 
 * @author 
 * @notice 提供getPool、createPool方法
 */
contract Factory is IFactory {
    // token0 => token1 => pools，一个交易对对应多个pool，不同的人添加的相同的交易对形成多个pool
    mapping(address => mapping(address => address[])) public pools;
    // 在IFactory中定义
    /*
    IFactory 接口定义了一个 parameters() 函数，Factory 合约通过 Parameters public override parameters; 使用状态变量来重写这个函数
    Solidity 会自动为公共状态变量生成一个同名的 getter 函数，因此，当外部调用 parameters() 时，实际上访问的是这个状态变量 parameters 的 getter 函数，它返回 Parameters 结构体类型的数据
    这种设计模式允许合约使用状态变量来实现接口中定义的函数，这在工厂模式中很常见，用于临时存储创建池子的参数
    override 表示根据parameters变量自动生成的 getter 函数重写了 IFactory 接口中的 parameters() 函数
    外部合约可以通过 IFactory(factoryAddress).parameters() 调用 getter 函数来读取这些参数
    */
    Parameters public override parameters;

    function sortToken(
        address tokenA,
        address tokenB
    ) private pure returns (address, address) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function getPool(
        address tokenA,
        address tokenB,
        uint32 index
    ) external view override returns (address) {
        // 两种token不能相同
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "ZERO_ADDRESS");

        // Declare token0 and token1
        address token0;
        address token1;
        // 排序，token0的地址必须小于token1的地址
        (token0, token1) = sortToken(tokenA, tokenB); 
        // pools[token0][token1]返回的是pools，pools[index]得到pool
        return pools[token0][token1][index]; 
    }

    function createPool(
        address tokenA,
        address tokenB,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) external override returns (address pool) {
        // validate token's individuality
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");

        // Declare token0 and token1
        address token0;
        address token1;

        // sort token, avoid the mistake of the order
        (token0, token1) = sortToken(tokenA, tokenB);

        // get current all pools
        address[] memory existingPools = pools[token0][token1];

        // check if the pool already exists，如果该交易对的pools存在，则查看是否存在相同fee相同价格区间的pool
        for (uint256 i = 0; i < existingPools.length; i++) {
            IPool currentPool = IPool(existingPools[i]);
            // fee相同、价格区间的下限和上限相同即视为相同pool
            if (
                currentPool.tickLower() == tickLower &&
                currentPool.tickUpper() == tickUpper &&
                currentPool.fee() == fee
            ) {
                return existingPools[i];
            }
        }
        // 没有符合条件的pool，就新建一个pool
        // save pool info，Parameters在IFactory中定义
        // 这里通过给Factory的状态变量parameters赋值，然后再下边new Pool时，在Pool合约的constructor中调用IFactory的parameters方法，获取Parameters中的各属性值来创建pool合约
        // 而Pool的constructor没有参数是为了保证创建Pool合约时参数的确定性
        parameters = Parameters({
            factory: address(this), // 记录增加该交易对的钱包
            tokenA: token0,
            tokenB: token1,
            tickLower: tickLower,
            tickUpper: tickUpper,
            fee: fee
        });

        // 根据token0, token1, tickLower, tickUpper, fee生成一个hash，其他人也能根据token0, token1, tickLower, tickUpper, fee生成相同hash
        bytes32 salt = keccak256(
            abi.encode(token0, token1, tickLower, tickUpper, fee)
        );

        // Pool是一个合约，该合约的address，通过指定盐值的方式创建，这样别人可以根据相同salt得到相同的pool的address
        pool = address(new Pool{salt: salt}());

        // save created pool，将该新pool插入token0、token1交易对的pools中
        pools[token0][token1].push(pool);

        // delete pool info，上边创建Pool合约时用完了parameters，这里就可以将parameters清空了
        delete parameters;

        emit PoolCreated(
            token0,
            token1,
            uint32(existingPools.length),
            tickLower,
            tickUpper,
            fee,
            pool
        );
    }
}
