// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

//  ___  _____  _  _    __      ___  ____  ____  ____    __    __  __
// / __)(  _  )( \( )  /__\    / __)(_  _)(  _ \( ___)  /__\  (  \/  )
// \__ \ )(_)(  )  (  /(__)\   \__ \  )(   )   / )__)  /(__)\  )    (
// (___/(_____)(_)\_)(__)(__)  (___/ (__) (_)\_)(____)(__)(__)(_/\/\_)

import { ISonaRewardToken } from "./interfaces/ISonaRewardToken.sol";
import { SonaMinter } from "./access/SonaMinter.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { AddressableTokenId } from "./utils/AddressableTokenId.sol";
import { ZeroCheck } from "./utils/ZeroCheck.sol";

contract SonaRewardToken is SonaMinter, ISonaRewardToken {
	using AddressableTokenId for uint256;
	using ZeroCheck for address;

	/*//////////////////////////////////////////////////////////////
	/                         MAPPINGS
	//////////////////////////////////////////////////////////////*/

	mapping(uint256 => ISonaRewardToken.RewardToken) public rewardTokens;

	/*//////////////////////////////////////////////////////////////
	/	                        MODIFIERS
	//////////////////////////////////////////////////////////////*/

	/// @dev Modifier that ensures the calling contract has the admin role
	modifier onlySonaAdminOrCreator(uint256 _tokenId) {
		if (_tokenId.getAddress() != msg.sender && !isSonaAdmin(msg.sender))
			revert SonaRewardToken_Unauthorized();
		_;
	}

	modifier onlyTokenHolder(uint256 _tokenId) {
		if (_ownerOf[_tokenId] != msg.sender) revert SonaRewardToken_Unauthorized();
		_;
	}

	/// @dev Modifier that ensures the tokenId has been minted
	modifier checkExists(uint256 _tokenId) {
		if (tokenIdExists(_tokenId)) {
			_;
		} else {
			revert SonaRewardToken_TokenIdDoesNotExist();
		}
	}

	/*//////////////////////////////////////////////////////////////
	/                         CONSTRUCTOR
	//////////////////////////////////////////////////////////////*/
	constructor() ERC721("", "") {
		_disableInitializers();
	}

	/*//////////////////////////////////////////////////////////////
	/                         FUNCTIONS
	//////////////////////////////////////////////////////////////*/

	/// @dev Initializes the contract
	function initialize(
		string calldata _name,
		string calldata _symbol,
		address _eoaAdmin,
		address _minter
	) external override initializer {
		// Setup role for contract creator, otherwise subsequent checks will not work
		_setupRole(_ADMIN_ROLE, _eoaAdmin);
		_setRoleAdmin(_ADMIN_ROLE, _ADMIN_ROLE);
		SonaMinter.initialize(_minter);

		// Initialize ERC721
		name = _name;
		symbol = _symbol;
	}

	/// @notice auth-guarded mint function
	/// @dev This is meant to be pluggable and allow for the evolution of mint
	///  			logic as the protocol evolves
	/// @param _owner The address the token will me minted to
	/// @param _tokenId The ID of the token that will be minted
	/// @param _arweaveTxId the arweave txId of the token metadata stored on arweave
	/// @param _payout the address to distribute funds to, potentially to split them with collaborators
	function mint(
		address _owner,
		uint256 _tokenId,
		string calldata _arweaveTxId,
		address payable _payout
	) external onlySonaMinter {
		_mint(_owner, _tokenId);
		_setTokenMetadata(_tokenId, _arweaveTxId, _payout);
	}

	/// @notice auth-guarded mint function
	/// @dev This is for artists to batch mint existing library to the protocol
	/// @param _metadatas The array tokens to be minted
	function mintMultipleToArtist(
		TokenMetadata[] calldata _metadatas
	) external onlySonaMinter {
		for (uint i = 0; i < _metadatas.length; i++) {
			_mint(_metadatas[i].tokenId.getAddress(), _metadatas[i].tokenId);
			_setTokenMetadata(
				_metadatas[i].tokenId,
				_metadatas[i].arweaveTxId,
				_metadatas[i].payout
			);
		}
	}

	/// @dev Updates the IPFS CID for the metadata for a given RewardToken
	/// @param _tokenId The ID of the token that will be updated
	/// @param _txId The metadata's IPFS CID
	function updateArweaveTxId(
		uint256 _tokenId,
		string calldata _txId
	) external checkExists(_tokenId) onlySonaAdminOrCreator(_tokenId) {
		_updateArweaveTxId(_tokenId, _txId);
	}

	/// @dev Updates the Payout address for a token
	/// @param _tokenId The ID of the token that will be updated
	/// @param _payout The new payout address to be used. Set to address(0) if funds should be sent directly to the claimant
	function updatePayoutAddress(
		uint256 _tokenId,
		address payable _payout
	) external checkExists(_tokenId) onlyTokenHolder(_tokenId) {
		rewardTokens[_tokenId].payout = _payout;

		emit PayoutAddressUpdated(_tokenId, _payout);
	}

	/// @dev Get a RewardToken's metadata from IPFS
	/// @param _tokenId The ID of the token to fetch
	function tokenURI(
		uint256 _tokenId
	)
		public
		view
		override(ERC721, ISonaRewardToken)
		checkExists(_tokenId)
		returns (string memory)
	{
		return string(abi.encodePacked("ar://", rewardTokens[_tokenId].arTxId));
	}

	/// @dev Returns the metadata of the RewardToken
	/// @param _tokenId The ID of the token to fetch
	function getRewardTokenMetadata(
		uint256 _tokenId
	) external view checkExists(_tokenId) returns (RewardToken memory metadata) {
		return rewardTokens[_tokenId];
	}

	/// @dev Returns the splits address of the RewardToken
	/// @param _tokenId The ID of the token to fetch
	function getRewardTokenPayoutAddr(
		uint256 _tokenId
	) external view checkExists(_tokenId) returns (address payable payout) {
		return rewardTokens[_tokenId].payout;
	}

	/// @notice Check if token `_tokenId` exists
	/// @param _tokenId The ID of the token to check
	/// @return exists a boolean
	function tokenIdExists(uint256 _tokenId) public view returns (bool exists) {
		return _ownerOf[_tokenId].isNotZero();
	}

	/*//////////////////////////////////////////////////////////////
	/                    INTERNAL FUNCTIONS
	//////////////////////////////////////////////////////////////*/
	function _updateArweaveTxId(
		uint256 _tokenId,
		string calldata _txId
	) internal {
		rewardTokens[_tokenId].arTxId = _txId;

		emit RewardTokenArweaveTxIdUpdated({ tokenId: _tokenId, txId: _txId });
	}

	function _setTokenMetadata(
		uint256 _tokenId,
		string calldata _txId,
		address payable _payout
	) internal {
		rewardTokens[_tokenId] = RewardToken({ arTxId: _txId, payout: _payout });

		emit RewardTokenMetadataUpdated({
			tokenId: _tokenId,
			txId: _txId,
			payout: _payout
		});
	}
}
