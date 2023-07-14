// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import { AuctionSigner } from "../../contracts/test/utils/AuctionSigner.sol";
import { SonaReserveAuction } from "../../contracts/SonaReserveAuction.sol";

contract PopulateAuction is Script, AuctionSigner {
	uint256 artistKey =
		0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

	function run() public {
		require(block.chainid == 999, "chain ID must be 999");

		auction = SonaReserveAuction(vm.envAddress("SONA_AUCTION"));
		MetadataBundle[2] memory bundles = _createBundles();
		Signature[2] memory sigs = _getBundleSignatures(bundles);

		vm.broadcast(artistKey);
		auction.createReserveAuction(bundles, sigs, address(0), 0.5 ether);
	}

	function _createBundles()
		private
		pure
		returns (MetadataBundle[2] memory bundles)
	{
		MetadataBundle memory artistBundle = MetadataBundle({
			arweaveTxId: "Hello World4!",
			tokenId: 0x70997970C51812dc3A010C7d01b50e0d17dc79C800000000000000000000004a,
			payout: payable(address(0)),
			rewardsPayout: payable(address(0))
		});
		MetadataBundle memory collectorBundle = MetadataBundle({
			arweaveTxId: "Hello World4",
			tokenId: 0x70997970C51812dc3A010C7d01b50e0d17dc79C800000000000000000000004b,
			payout: payable(address(0)),
			rewardsPayout: payable(address(0))
		});

		bundles = [artistBundle, collectorBundle];
	}
}

// Cast can now be used to interact with contracts, for intance;

// 1. creating a bid
// cast send $SONA_AUCTION "createBid(uint256,uint256)" --rpc-url $RPC_URL 0x70997970C51812dc3A010C7d01b50e0d17dc79C800000000000000000000004b 0 --value 50000000000000000 -i

// 2. settling an auction
// cast send $SONA_AUCTION "createBid(uint256,uint256)" --rpc-url $RPC_URL 0x70997970C51812dc3A010C7d01b50e0d17dc79C800000000000000000000004b 0 --value 50000000000000000 -i
