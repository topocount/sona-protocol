// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

//  ___  _____  _  _    __      ___  ____  ____  ____    __    __  __
// / __)(  _  )( \( )  /__\    / __)(_  _)(  _ \( ___)  /__\  (  \/  )
// \__ \ )(_)(  )  (  /(__)\   \__ \  )(   )   / )__)  /(__)\  )    (
// (___/(_____)(_)\_)(__)(__)  (___/ (__) (_)\_)(____)(__)(__)(_/\/\_)

interface ISonaRewardToken {
	error SonaRewardToken_DoesNotExist();

	error SonaRewardToken_TokenIdDoesNotExist();

	error SonaRewardToken_Unauthorized();

	error SonaRewardToken_ArtistEditionEven();

	error SonaRewardToken_NoArtistInTokenId();

	/*//////////////////////////////////////////////////////////////
	/                              EVENTS
	//////////////////////////////////////////////////////////////*/

	/// @dev Emitted when a new RewardToken is minted.
	/// @param tokenId The id of the token
	/// @param cid The cid of the RewardToken
	event RewardTokenMinted(uint256 indexed tokenId, string cid);

	/// @dev Emitted when a RewardToken's metadata is changed.
	/// @param tokenId The id of the token
	/// @param txId The cid of the RewardToken
	event RewardTokenArweaveTxIdUpdated(uint256 tokenId, string txId);

	/// @dev Emitted when a RewardToken's metadata is changed.
	/// @param tokenId The id of the token
	/// @param txId The cid of the RewardToken
	event RewardTokenMetadataUpdated(uint256 indexed tokenId, string txId, address splits);

	/// @dev Emitted when a RewardToken is removed.
	/// @param tokenId The id of the RewardToken
	event RewardTokenRemoved(uint256 indexed tokenId);

	/// @dev Emitted when a RewardToken minter is initialized
	/// @param owner The owner of the contract
	/// @param name The name of the contract
	/// @param symbol The symbol of the contract
	event Initialized(address owner, string name, string symbol);

	/*//////////////////////////////////////////////////////////////
	/                             STRUCTS
	//////////////////////////////////////////////////////////////*/

	struct RewardToken {
		/// @dev The hash of the Arweave transaction where the metadata is stored.
		string arTxId;
		/// @dev The address of a splits contract for sharing rewards with collaborators
		address payable splits;
	}

	/*//////////////////////////////////////////////////////////////
	/                            FUNCTIONS
	//////////////////////////////////////////////////////////////*/

	function mintFromAuction(uint256 _tokenId, address _artist, address _collector, string memory _artistCid, string memory _collectorCid, address payable _splits) external;

	function updateArweaveTxId(uint256 _tokenId, string calldata _TxId) external;

	function burnRewardToken(uint256 _tokenId) external;

	function tokenURI(uint256 _tokenId) external view returns (string memory);

	function getRewardTokenMetadata(uint256 _tokenId) external view returns (RewardToken memory metadata);

	function getRewardTokenSplitsAddr(uint256 _tokenId) external view returns (address payable splits);

	function initialize(string memory _name, string memory _symbol, address _eoaAdmin, address _minter) external;

	function tokenIdExists(uint256 _tokenId) external view returns (bool exists);
}
