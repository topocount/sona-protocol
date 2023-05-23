// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { ISonaReserveAuction } from "../../interfaces/ISonaReserveAuction.sol";

contract ContractBidderMock {
	ISonaReserveAuction public auction;

	error CannotReceiveEther();

	bool public canReceiveFunds;

	constructor(ISonaReserveAuction auction_) {
		auction = auction_;
		canReceiveFunds = true;
	}

	function createETHBid(
		uint256 _tokenId,
		uint256 _ethBidAmount
	) external payable {
		auction.createBid{ value: _ethBidAmount }(_tokenId, 0);
	}

	// Fallback function to receive ETH refunds
	fallback() external payable {}

	// Receive function to accept plain Ether transfers conditionally
	receive() external payable {
		if (!canReceiveFunds) revert CannotReceiveEther();
	}

	// Function to disable the receive function
	function disableReceiving() external {
		canReceiveFunds = false;
	}
}
