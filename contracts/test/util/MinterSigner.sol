// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { SonaRewardToken, ISonaRewardToken } from "../../SonaRewardToken.sol";
import { SonaDirectMint } from "../../SonaDirectMint.sol";
import { SonaTokenAuthorizor } from "../../SonaTokenAuthorizor.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { Util } from "../Util.sol";
import { VmSafe } from "forge-std/Vm.sol";

abstract contract MinterSigner is SonaTokenAuthorizor {
	address private constant _VMSAFE_ADDRESS =
		address(uint160(uint256(keccak256("hevm cheat code"))));
	VmSafe internal constant _vmLocal = VmSafe(_VMSAFE_ADDRESS);

	string public mnemonic =
		"test test test test test test test test test test test junk";
	uint256 public authorizorKey = _vmLocal.deriveKey(mnemonic, 0);

	address public authorizor = _vmLocal.addr(authorizorKey);
	bytes32 public domainSeparator;

	function _makeDomainHash(string memory name, address _verifier) internal {
		domainSeparator = keccak256(
			abi.encode(
				_EIP712DOMAIN_TYPEHASH,
				keccak256(abi.encodePacked(name)), // name
				keccak256("1"), // version
				block.chainid, // chain ID
				_verifier // verifying contract
			)
		);
	}

	function _hashFromMemory(
		ISonaRewardToken.TokenMetadata memory bundle
	) internal pure returns (bytes32) {
		return
			keccak256(
				abi.encode(
					_METADATABUNDLE_TYPEHASH,
					bundle.tokenId,
					bundle.payout,
					keccak256(bytes(bundle.metadataId))
				)
			);
	}

	function _hashFromMemory(
		ISonaRewardToken.TokenMetadata[] memory _metadatas
	) internal pure returns (bytes32) {
		bytes32[] memory hashedBundles = new bytes32[](_metadatas.length);

		for (uint i = 0; i < _metadatas.length; i++) {
			hashedBundles[i] = _hashFromMemory(_metadatas[i]);
		}
		return
			keccak256(
				abi.encode(
					_METADATABUNDLES_TYPEHASH,
					keccak256(abi.encodePacked(hashedBundles))
				)
			);
	}

	function _getBundlesHash(
		ISonaRewardToken.TokenMetadata[] memory _metadatas
	) internal view returns (bytes32) {
		return
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					domainSeparator,
					_hashFromMemory(_metadatas)
				)
			);
	}

	function _signBundles(
		ISonaRewardToken.TokenMetadata[] memory _metadatas
	) internal view returns (Signature memory signature) {
		bytes32 bundleHash = _getBundlesHash(_metadatas);
		(uint8 v, bytes32 r, bytes32 s) = _vmLocal.sign(authorizorKey, bundleHash);

		return Signature({ v: v, r: r, s: s });
	}
}
