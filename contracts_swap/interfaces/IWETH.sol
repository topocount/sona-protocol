// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.7.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

interface IWETH is IERC20 {
	event Deposit(address indexed dst, uint wad);
	event Withdrawal(address indexed src, uint wad);

	function deposit() external payable;

	function withdraw(uint wad) external;
}
