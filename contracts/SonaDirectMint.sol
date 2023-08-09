// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

//  ___  _____  _  _    __      ___  ____  ____  ____    __    __  __
// / __)(  _  )( \( )  /__\    / __)(_  _)(  _ \( ___)  /__\  (  \/  )
// \__ \ )(_)(  )  (  /(__)\   \__ \  )(   )   / )__)  /(__)\  )    (
// (___/(_____)(_)\_)(__)(__)  (___/ (__) (_)\_)(____)(__)(__)(_/\/\_)

import { ISonaRewardToken } from "./interfaces/ISonaRewardToken.sol";
import { AddressableTokenId } from "./utils/AddressableTokenId.sol";
import { SonaTokenAuthorizer } from "./SonaTokenAuthorizer.sol";

contract SonaDirectMint is SonaTokenAuthorizer {
	using AddressableTokenId for uint256;

	/*//////////////////////////////////////////////////////////////
	/                         STATE
	//////////////////////////////////////////////////////////////*/

	// @dev The instance of the rewardToken contract
	ISonaRewardToken public token;

	/*//////////////////////////////////////////////////////////////
	/                         MODIFIERS
	//////////////////////////////////////////////////////////////*/

	modifier bundlesAuthorized(
		ISonaRewardToken.TokenMetadatas calldata _bundles,
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
		ISonaRewardToken.TokenMetadatas calldata _bundles,
		Signature calldata _signature
	) external bundlesAuthorized(_bundles, _signature) {
		token.mintMulipleToArtist(_bundles.bundles);
	}
}
