// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title Tax handler interface
 * @dev Any class that implements this interface can be used for protocol-specific tax calculations.
 * @title 税务处理接口
 * @dev 用于协议自定义税务逻辑（如交易税、手续费等）
 */
interface ITaxHandler {
    /**
     * @notice Get number of tokens to pay as tax.
     * @param benefactor Address of the benefactor.
     * @param beneficiary Address of the beneficiary.
     * @param amount Number of tokens in the transfer.
     * @return Number of tokens to pay as tax.
     */
    /**
     * @notice 计算交易应缴纳的税额
     * @dev 例如：NFT交易税 = 5% * 交易金额，或流动性池的动态税率
     * @param benefactor 交易发起方（如卖方）
     * @param beneficiary 交易接收方（如买方）
     * @param amount 交易原始金额
     * @return 应缴纳的税额（需扣除到协议地址）
     */
    function getTax(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external view returns (uint256);
}