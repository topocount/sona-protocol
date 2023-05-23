// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { IWETH } from "../../interfaces/IWETH.sol";

contract Weth9Mock is IWETH {
	string public name = "Mock Wrapped Ether";
	string public symbol = "mWETH";
	uint8 public decimals = 18;

	mapping(address => uint) public balanceOf;
	mapping(address => mapping(address => uint)) public allowance;

	receive() external payable {
		deposit();
	}

	function deposit() public payable virtual {
		emit Deposit(msg.sender, msg.value);
	}

	function withdraw(uint wad) public virtual {
		payable(msg.sender).transfer(wad);
		emit Withdrawal(msg.sender, wad);
	}

	function totalSupply() public view virtual returns (uint) {
		return address(this).balance;
	}

	function approve(address guy, uint wad) public virtual returns (bool) {
		allowance[msg.sender][guy] = wad;
		emit Approval(msg.sender, guy, wad);
		return true;
	}

	function transfer(address dst, uint wad) public virtual returns (bool) {
		return transferFrom(msg.sender, dst, wad);
	}

	function transferFrom(
		address src,
		address dst,
		uint wad
	) public virtual returns (bool) {
		require(totalSupply() >= wad, "mock weth: low balance");
		emit Transfer(src, dst, wad);

		unchecked {
			balanceOf[dst] += wad;
			balanceOf[src] -= wad;
		}

		return true;
	}
}
