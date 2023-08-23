// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

//  ___  _____  _  _    __      ___  ____  ____  ____    __    __  __
// / __)(  _  )( \( )  /__\    / __)(_  _)(  _ \( ___)  /__\  (  \/  )
// \__ \ )(_)(  )  (  /(__)\   \__ \  )(   )   / )__)  /(__)\  )    (
// (___/(_____)(_)\_)(__)(__)  (___/ (__) (_)\_)(____)(__)(__)(_/\/\_)

import { ISonaTokenAuthorizer } from "./interfaces/ISonaTokenAuthorizer.sol";
import { ISonaRewardToken } from "./interfaces/ISonaRewardToken.sol";

contract SonaTokenAuthorizer is ISonaTokenAuthorizer {
	/*//////////////////////////////////////////////////////////////
	/                         CONSTANTS
	//////////////////////////////////////////////////////////////*/

	/// @dev The signature of the Domain separator typehash
	bytes32 internal constant _EIP712DOMAIN_TYPEHASH =
		keccak256(
			"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
		);
	/// @dev The signature of the type that is hashed and prefixed to the TypedData payload
	bytes32 internal constant _METADATABUNDLE_TYPEHASH =
		keccak256(
			"TokenMetadata(uint256 tokenId,address payout,string arweaveTxId)"
		);
	/// @dev The signature of the type that is hashed and prefixed to the TypedData payload
	bytes32 internal constant _METADATABUNDLES_TYPEHASH =
		keccak256(
			"TokenMetadatas(TokenMetadata[] bundles)TokenMetadata(uint256 tokenId,address payout,string arweaveTxId)"
		);
	/// @dev part of the EIP-712 standard for structured data hashes
	bytes32 internal _DOMAIN_SEPARATOR;

	/*//////////////////////////////////////////////////////////////
	/                         STATE
	//////////////////////////////////////////////////////////////*/

	/// @dev the address of the authorizing signer;
	/// initialized to 0xdead to prevent uninitialized authorization
	address internal _authorizer = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;

	/*//////////////////////////////////////////////////////////////
	/                    PRIVATE FUNCTIONS
	//////////////////////////////////////////////////////////////*/

	function _makeDomainSeparator(string calldata name) internal {
		_DOMAIN_SEPARATOR = keccak256(
			abi.encode(
				_EIP712DOMAIN_TYPEHASH,
				keccak256(abi.encodePacked(name)), // name
				keccak256("1"), // version
				block.chainid, // chain ID
				address(this) // verifying contract
			)
		);
	}

	function _verify(
		ISonaRewardToken.TokenMetadata[] calldata _metadatas,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal view returns (bool valid) {
		return _recoverAddress(_metadatas, v, r, s) == _authorizer;
	}

	function _recoverAddress(
		ISonaRewardToken.TokenMetadata[] calldata _metadatas,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal view returns (address recovered) {
		// Note: we need to use `encodePacked` here instead of `encode`.
		bytes32 digest = keccak256(
			abi.encodePacked("\x19\x01", _DOMAIN_SEPARATOR, _hash(_metadatas))
		);
		recovered = ecrecover(digest, v, r, s);
	}

	function _hash(
		ISonaRewardToken.TokenMetadata calldata _bundle
	) internal pure returns (bytes32) {
		return
			keccak256(
				abi.encode(
					_METADATABUNDLE_TYPEHASH,
					_bundle.tokenId,
					_bundle.payout,
					keccak256(bytes(_bundle.arweaveTxId))
				)
			);
	}

	function _hash(
		ISonaRewardToken.TokenMetadata[] calldata _metadatas
	) internal pure returns (bytes32) {
		bytes32[] memory hashedBundles = new bytes32[](_metadatas.length);

		for (uint i = 0; i < _metadatas.length; i++) {
			hashedBundles[i] = _hash(_metadatas[i]);
		}
		return
			keccak256(
				abi.encode(
					_METADATABUNDLES_TYPEHASH,
					keccak256(abi.encodePacked(hashedBundles))
				)
			);
	}
}
