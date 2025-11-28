// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.25;
/*
### ✅ 作业 1：ERC20 代币
任务：参考 openzeppelin-contracts/contracts/token/ERC20/IERC20.sol实现一个简单的 ERC20 代币合约。要求：
1. 合约包含以下标准 ERC20 功能：
2. balanceOf：查询账户余额。
3. transfer：转账。
4. approve 和 transferFrom：授权和代扣转账。
5. 使用 event 记录转账和授权操作。
6. 提供 mint 函数，允许合约所有者增发代币。
提示：
- 使用 mapping 存储账户余额和授权信息。
- 使用 event 定义 Transfer 和 Approval 事件。
4. 部署到sepolia 测试网，导入到自己的钱包
*/
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
contract MyToken is ERC20, ERC20Permit, Ownable {
    /*继承ERC20Permit
    无 Gas 授权：用户无需发送链上交易进行授权，而是通过链下离线签名完成授权操作，完全避免了授权所需的 Gas 费用。
    简化交易流程：将传统 ERC-20 需要的两次链上交易（先 approve 授权，再 transferFrom 转账）合并为一次交易，大大简化了操作流程。
    提升用户体验：特别适合钱包中没有 ETH 的新手用户，无需先进行授权操作就能直接使用代币
    */

    // 调用Ownable(msg.sender)，将代币合约的owner设为该代币合约的发型者
    constructor (string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC20Permit(name_) Ownable(msg.sender){
        // 向部署者铸造1亿个
        _mint(msg.sender, 1e8 * 10 ** 18);
    }

    //提供 mint 函数，仅允许合约所有者增发代币。
    function mint(uint256 amount) public onlyOwner{
        _mint(msg.sender, amount);
    }
    /*
    // 首先由transferFrom中的from参数调用approve，from.approve(spender, value), 然后由spender调用transferFrom，spender.transferFrom(from, to, value)
    //函数调用者是代币持有者，spender是被授权的人或合约，value是授权的代币数量，
        function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        // 将授权本spender，允许函数调用者的钱包中操作value数量的代币
        // 
        _approve(owner, spender, value);
        return true;
    }
    */

    /* 
    //由第三方调用，即approve函数中的spender调用，而from为approve的调用者
        function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }
    */

    /*
    //用户调用transfer函数，将自己的value个代币转给to地址，在hardhat中，如果调用taskTwoErc20.transfer(account2, 100)，即合约的默认部署账户（owner）account1，将自己钱包里的token转给account2
        function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }
    */

}