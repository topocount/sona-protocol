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
		if (_tokenId.getAddress() != msg.sender && !isSonaAdmin(msg.sender)) revert SonaRewardToken_Unauthorized();
		_;
	}

	modifier onlyTokenHolder(uint256 _tokenId) {
		if (_ownerOf[_tokenId] != msg.sender) revert SonaRewardToken_Unauthorized();
		_;
	}

	/// @dev Modifier that ensures the tokenId has been minted and not burned
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
	function initialize(string calldata _name, string calldata _symbol, address _eoaAdmin, address _minter) external override initializer {
		// Setup role for contract creator, otherwise subsequent checks will not work
		_setupRole(_ADMIN_ROLE, _eoaAdmin);
		_setRoleAdmin(_ADMIN_ROLE, _ADMIN_ROLE);
		SonaMinter.initialize(_minter);

		// Initialize ERC721
		name = _name;
		symbol = _symbol;
	}

	/// @notice this mint function is called by an auction contract
	/// @dev only an account with the SonaMinter role can call this function
	/// @param _tokenId The ID of the token that will be minted
	/// @param _artist The address contained in the tokenId
	/// @param _collector The address that won the auction
	/// @param _artistTxId the arweave txId of the artist edition bundle contained on arweave
	/// @param _collectorTxId the arweave txId of the collector edition bundle contained on arweave
	/// @param _splits the address to distribute funds to, potentially to split them with collaborators
	function mintFromAuction(uint256 _tokenId, address _artist, address _collector, string calldata _artistTxId, string calldata _collectorTxId, address payable _splits) external onlySonaMinter {
		if (_tokenId % 2 == 0) revert SonaRewardToken_ArtistEditionEven();
		if (AddressableTokenId.getAddress(_tokenId) != _artist) revert SonaRewardToken_NoArtistInTokenId();
		uint256 artistTokenId = _tokenId.getArtistEdition();
		_mint(_artist, artistTokenId);
		_setTokenMetadata(artistTokenId, _artistTxId, _splits);

		_mint(_collector, _tokenId);
		_setTokenMetadata(_tokenId, _collectorTxId, payable(address(0)));
	}

	/// @dev Updates the IPFS CID for the metadata for a given RewardToken
	/// @param _tokenId The ID of the token that will be updated
	/// @param _txId The metadata's IPFS CID
	function updateArweaveTxId(uint256 _tokenId, string calldata _txId) external checkExists(_tokenId) onlySonaAdminOrCreator(_tokenId) {
		_updateArweaveTxId(_tokenId, _txId);
	}

	/// @dev Removes a RewardToken from the protocol, burning the NFT and striking the data from on-chain memory
	/// @param _tokenId The ID of the token that will be deleted
	function burnRewardToken(uint256 _tokenId) external onlyTokenHolder(_tokenId) {
		delete rewardTokens[_tokenId];

		_burn(_tokenId);

		emit RewardTokenRemoved({ tokenId: _tokenId });
	}

	/// @dev Get a RewardToken's metadata from IPFS
	/// @param _tokenId The ID of the token to fetch
	function tokenURI(uint256 _tokenId) public view override(ERC721, ISonaRewardToken) checkExists(_tokenId) returns (string memory) {
		return string(abi.encodePacked("ar://", rewardTokens[_tokenId].arTxId));
	}

	/// @dev Returns the metadata of the RewardToken
	/// @param _tokenId The ID of the token to fetch
	function getRewardTokenMetadata(uint256 _tokenId) external view checkExists(_tokenId) returns (RewardToken memory metadata) {
		return rewardTokens[_tokenId];
	}

	/// @dev Returns the splits address of the RewardToken
	/// @param _tokenId The ID of the token to fetch
	function getRewardTokenSplitsAddr(uint256 _tokenId) external view checkExists(_tokenId) returns (address payable splits) {
		return rewardTokens[_tokenId].splits;
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
	function _updateArweaveTxId(uint256 _tokenId, string calldata _txId) internal {
		rewardTokens[_tokenId].arTxId = _txId;

		emit RewardTokenArweaveTxIdUpdated({ tokenId: _tokenId, txId: _txId });
	}

	function _setTokenMetadata(uint256 _tokenId, string calldata _txId, address payable _splits) internal {
		rewardTokens[_tokenId] = RewardToken({ arTxId: _txId, splits: _splits });

		emit RewardTokenMetadataUpdated({ tokenId: _tokenId, txId: _txId, splits: _splits });
	}
}
