// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { ERC721ConsecutiveEnumerableMock } from "openzeppelin/mocks/token/ERC721ConsecutiveEnumerableMock.sol";

contract RewardTokenMock is ERC721ConsecutiveEnumerableMock {
	address payable public altAddress;

	constructor(
		string memory name,
		string memory symbol,
		address[] memory receivers,
		uint96[] memory amounts,
		address payable _altAddress
	) ERC721ConsecutiveEnumerableMock(name, symbol, receivers, amounts) {
		altAddress = _altAddress;
	}

	function setSplitAddr(address payable _newSplit) public {
		altAddress = _newSplit;
	}

	function getRewardTokenPayoutAddr(
		uint256 /*tokenId*/
	) external view returns (address payable splits) {
		return altAddress;
	}
}
