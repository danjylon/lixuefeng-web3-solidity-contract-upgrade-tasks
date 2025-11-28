// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

/// @title TransferHelper
/// @notice Contains helper methods for interacting with ERC20 tokens that do not consistently return true/false
library TransferHelper {
    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Calls transfer on token contract, errors with TF if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(address token, address to, uint256 value) internal {
        // console.log("TransferHelper.safeTransfer.token: ", token);
        // console.log("TransferHelper.safeTransfer.to: ", to);
        // console.log("TransferHelper.safeTransfer.value: ", value);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        // console.log("TransferHelper.safeTransfer.success: ", success);
        // console.log("TransferHelper.safeTransfer.data.length: ", data.length);
        // 问题，为什么除了判断success外，还要判断(data.length == 0 || abi.decode(data, (bool)))
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TF"
        );
    }
}
