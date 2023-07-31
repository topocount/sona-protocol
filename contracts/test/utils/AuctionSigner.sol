// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { SonaReserveAuction } from "../../SonaReserveAuction.sol";
import { VmSafe } from "forge-std/Vm.sol";

abstract contract AuctionSigner is SonaReserveAuction {
	address private constant _VMSAFE_ADDRESS =
		address(uint160(uint256(keccak256("hevm cheat code"))));
	VmSafe internal constant _vmLocal = VmSafe(_VMSAFE_ADDRESS);
	SonaReserveAuction public auction;

	string public mnemonic =
		"test test test test test test test test test test test junk";
	uint256 public authorizerKey = _vmLocal.deriveKey(mnemonic, 0);

	address public authorizer = _vmLocal.addr(authorizerKey);

	function _makeDomainHash() private view returns (bytes32) {
		bytes32 _EIP712DOMAIN_TYPEHASH = keccak256(
			"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
		);
		return
			keccak256(
				abi.encode(
					_EIP712DOMAIN_TYPEHASH,
					keccak256("SonaReserveAuction"), // name
					keccak256("1"), // version
					block.chainid, // chain ID
					address(auction) // verifying contract
				)
			);
	}

	function _hashFromMemory(
		MetadataBundle memory bundle
	) internal pure returns (bytes32) {
		bytes32 _METADATABUNDLE_TYPEHASH = keccak256(
			"MetadataBundle(uint256 tokenId,address payout,string arweaveTxId)"
		);
		return
			keccak256(
				abi.encode(
					_METADATABUNDLE_TYPEHASH,
					bundle.tokenId,
					bundle.payout,
					keccak256(bytes(bundle.arweaveTxId))
				)
			);
	}

	function _getBundleHash(
		MetadataBundle memory _bundle
	) internal view returns (bytes32) {
		bytes32 domainSeparator = _makeDomainHash();
		return
			keccak256(
				abi.encodePacked("\x19\x01", domainSeparator, _hashFromMemory(_bundle))
			);
	}

	function _signBundle(
		MetadataBundle memory _bundle
	) internal view returns (Signature memory signature) {
		bytes32 bundleHash = _getBundleHash(_bundle);
		(uint8 v, bytes32 r, bytes32 s) = _vmLocal.sign(authorizerKey, bundleHash);

		return Signature({ v: v, r: r, s: s });
	}

	function _getBundleSignatures(
		MetadataBundle[2] memory _bundles
	) internal view returns (Signature[2] memory signatures) {
		signatures[0] = _signBundle(_bundles[0]);
		signatures[1] = _signBundle(_bundles[1]);
	}
}
