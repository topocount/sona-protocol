// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

//  ___  _____  _  _    __      ___  ____  ____  ____    __    __  __
// / __)(  _  )( \( )  /__\    / __)(_  _)(  _ \( ___)  /__\  (  \/  )
// \__ \ )(_)(  )  (  /(__)\   \__ \  )(   )   / )__)  /(__)\  )    (
// (___/(_____)(_)\_)(__)(__)  (___/ (__) (_)\_)(____)(__)(__)(_/\/\_)

import { ISonaRewardToken } from "./interfaces/ISonaRewardToken.sol";
import { AddressableTokenId } from "./utils/AddressableTokenId.sol";
import { ISonaAuthorizer } from "./interfaces/ISonaAuthorizer.sol";

contract SonaDirectMint is ISonaAuthorizer {
	using AddressableTokenId for uint256;

	/*//////////////////////////////////////////////////////////////
	/                        STRUCTS
	//////////////////////////////////////////////////////////////*/

	struct TokenMetadatas {
		ISonaRewardToken.TokenMetadata[] bundles;
	}

	/*//////////////////////////////////////////////////////////////
	/                         CONSTANTS
	//////////////////////////////////////////////////////////////*/

	// @dev The signature of the Domain separator typehash
	bytes32 internal constant _EIP712DOMAIN_TYPEHASH =
		keccak256(
			"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
		);
	// @dev The signature of the type that is hashed and prefixed to the TypedData payload
	bytes32 internal constant _METADATABUNDLE_TYPEHASH =
		keccak256(
			"TokenMetadata(uint256 tokenId,address payout,string arweaveTxId)"
		);
	// @dev The signature of the type that is hashed and prefixed to the TypedData payload
	bytes32 internal constant _METADATABUNDLES_TYPEHASH =
		keccak256(
			"TokenMetadatas(TokenMetadata[] bundles)TokenMetadata(uint256 tokenId,address payout,string arweaveTxId)"
		);

	/*//////////////////////////////////////////////////////////////
	/                         STATE
	//////////////////////////////////////////////////////////////*/

	// @dev The instance of the rewardToken contract
	ISonaRewardToken public token;
	// @dev part of the EIP-712 standard for structured data hashes
	bytes32 internal _DOMAIN_SEPARATOR;
	// @dev the address of the authorizing signer
	address internal _authorizer;

	/*//////////////////////////////////////////////////////////////
	/                         MODIFIERS
	//////////////////////////////////////////////////////////////*/

	modifier bundlesAuthorized(
		TokenMetadatas calldata _bundles,
		Signature calldata _signature
	) {
		if (!_verify(_bundles, _signature.v, _signature.r, _signature.s))
			revert SonaAuthorizer_InvalidSignature();
		_;
	}

	/*//////////////////////////////////////////////////////////////
								Constructor
	//////////////////////////////////////////////////////////////*/
	constructor(ISonaRewardToken _token, address authorizer_) {
		token = _token;
		_authorizer = authorizer_;

		_DOMAIN_SEPARATOR = keccak256(
			abi.encode(
				_EIP712DOMAIN_TYPEHASH,
				keccak256("SonaDirectMint"), // name
				keccak256("1"), // version
				block.chainid, // chain ID
				address(this) // verifying contract
			)
		);
	}

	/*//////////////////////////////////////////////////////////////
	/                         FUNCTIONS
	//////////////////////////////////////////////////////////////*/

	function mint(
		TokenMetadatas calldata _bundles,
		Signature calldata _signature
	) external bundlesAuthorized(_bundles, _signature) {
		token.mintMulipleToArtist(_bundles.bundles);
	}

	/*//////////////////////////////////////////////////////////////
	/                    PRIVATE FUNCTIONS
	//////////////////////////////////////////////////////////////*/

	function _verify(
		TokenMetadatas calldata _bundles,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal view returns (bool valid) {
		return _recoverAddress(_bundles, v, r, s) == _authorizer;
	}

	function _recoverAddress(
		TokenMetadatas calldata _bundles,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal view returns (address recovered) {
		// Note: we need to use `encodePacked` here instead of `encode`.
		bytes32 digest = keccak256(
			abi.encodePacked("\x19\x01", _DOMAIN_SEPARATOR, _hash(_bundles))
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
		TokenMetadatas calldata _mdb
	) internal pure returns (bytes32) {
		bytes32[] memory hashedBundles = new bytes32[](_mdb.bundles.length);

		for (uint i = 0; i < _mdb.bundles.length; i++) {
			hashedBundles[i] = _hash(_mdb.bundles[i]);
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
