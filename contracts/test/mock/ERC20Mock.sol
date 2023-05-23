// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

contract ERC20ReturnTrueMock {
	mapping(address => uint) public balanceOf;
	mapping(address => mapping(address => uint)) public allowance;

	event Transfer(address indexed from, address indexed to, uint256 value);

	function transfer(address to, uint256 amount) public returns (bool) {
		unchecked {
			balanceOf[to] += amount;
			balanceOf[msg.sender] -= amount;
		}
		emit Transfer(msg.sender, to, amount);
		return true;
	}

	function transferFrom(
		address from,
		address to,
		uint256 amount
	) public returns (bool) {
		unchecked {
			balanceOf[to] += amount;
			balanceOf[from] -= amount;
		}
		emit Transfer(from, to, amount);
		return true;
	}
}

contract ERC20ReturnFalseMock {
	function transferFrom(
		address /*from*/,
		address /*to*/,
		uint256 /*amount*/
	) public pure returns (bool) {
		return false;
	}
}

contract ERC20NoReturnMock {
	function transferFrom(
		address /*from*/,
		address /*to*/,
		uint256 /*amount*/
	) public pure {
		return;
	}
}
