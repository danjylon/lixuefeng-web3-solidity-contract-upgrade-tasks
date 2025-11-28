// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;


import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract WETH is ERC20 {
    event  Deposit(address indexed to, uint amount);
    event  Withdrawal(address indexed from, uint amount);

    constructor() ERC20("Wrapped ETH", "WETH") {

    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }
    
    function withdraw(uint amount) public {
        // 查询提现者的weth余额够不够
        require(balanceOf(msg.sender) >= amount);
        // 将提现者的weth余额减去amount
        // _balances[msg.sender] -= amount;
        _transfer(msg.sender, address(this), amount);
        _burn(address(this), amount);
        // 向提现者转账amount个eth
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }

}