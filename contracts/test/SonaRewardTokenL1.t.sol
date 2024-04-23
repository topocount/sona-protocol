// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

//  ___  _____  _  _    __      ___  ____  ____  ____    __    __  __
// / __)(  _  )( \( )  /__\    / __)(_  _)(  _ \( ___)  /__\  (  \/  )
// \__ \ )(_)(  )  (  /(__)\   \__ \  )(   )   / )__)  /(__)\  )    (
// (___/(_____)(_)\_)(__)(__)  (___/ (__) (_)\_)(____)(__)(__)(_/\/\_)

import { SonaRewardTokenL1 as SonaRewardToken, AddressableTokenId } from "../SonaRewardTokenL1.sol";
import { SonaReserveAuction } from "../SonaReserveAuction.sol";
import { IERC721AUpgradeable } from "erc721a-upgradeable/IERC721AUpgradeable.sol";
import { ERC721Holder } from "openzeppelin/token/ERC721/utils/ERC721Holder.sol";
import { ISonaRewardToken } from "../interfaces/ISonaRewardToken.sol";
import { IERC721Bridge } from "../interfaces/IL1ERC721Bridge.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { Util } from "./Util.sol";

contract SonaRewardTokenTest is Util, ERC721Holder, SonaRewardToken {
	using AddressableTokenId for uint256;
	// treasury address getting the fees
	address public treasuryRecipient = makeAddr("treasuryRecipient");
	// redistribution address getting the fees
	address public redistributionRecipient = makeAddr("redistributionRecipient");
	// reward token recipient
	address public rewardTokenRecipient = makeAddr("rewardTokenRecipient");
	// auction mock
	address public tokenAdmin = makeAddr("tokenAdmin");

	address payable public zeroSplitsAddr = payable(address(0));
	address payable public payoutAddr = payable(makeAddr("splitAddress"));

	uint256 private _tokenId = (uint256(uint160(address(this))) << 96) | 3;
	uint256 private _artistTokenId = (uint256(uint160(address(this))) << 96) | 2;

	SonaRewardToken public rewardToken;

	uint256 public mainnetFork;
	string public MAINNET_RPC_URL = vm.envString("MAINNET_FORK_RPC_URL");

	/// @notice Emitted when an ERC721 bridge to the other network is initiated.
	/// @param localToken  Address of the token on this domain.
	/// @param remoteToken Address of the token on the remote domain.
	/// @param from        Address that initiated bridging action.
	/// @param to          Address to receive the token.
	/// @param tokenId     ID of the specific token deposited.
	/// @param extraData   Extra data for use on the client-side.
	event ERC721BridgeInitiated(
		address indexed localToken,
		address indexed remoteToken,
		address indexed from,
		address to,
		uint256 tokenId,
		bytes extraData
	);

	function setUp() public {
		SonaRewardToken rewardTokenBase = new SonaRewardToken();
		ERC1967Proxy proxy = new ERC1967Proxy(
			address(rewardTokenBase),
			abi.encodeWithSelector(
				SonaRewardToken.initialize.selector,
				"SonaRewardToken",
				"SRT",
				address(tokenAdmin),
				address(this),
				"http://fakeSona.stream"
			)
		);

		rewardToken = SonaRewardToken(address(proxy));
		hoax(tokenAdmin);
		rewardToken.grantRole(keccak256("MINTER_ROLE"), address(this));
	}

	function test_UnauthorizedMintReverts(address badMinter) public {
		vm.assume(badMinter != tokenAdmin);
		vm.assume(badMinter != address(this));

		vm.prank(badMinter);
		vm.expectRevert();
		rewardToken.mint(rewardTokenRecipient, _tokenId, "", zeroSplitsAddr);

		ISonaRewardToken.TokenMetadata memory bundle = ISonaRewardToken
			.TokenMetadata({
				tokenId: 12345,
				payout: payable(address(0)),
				metadataId: "cool NFT"
			});
		ISonaRewardToken.TokenMetadata[]
			memory bundles = new ISonaRewardToken.TokenMetadata[](1);
		bundles[0] = bundle;
		vm.prank(badMinter);
		vm.expectRevert();
		rewardToken.mintMultipleToArtist(bundles);
	}

	function test_initializedParams() public {
		rewardToken.name;
		assertEq(rewardToken.name(), "SonaRewardToken");
		assertEq(rewardToken.symbol(), "SRT");
	}

	function test_InvalidTokenIDOnTokenURIExistsReverts() public {
		vm.expectRevert(
			ISonaRewardToken.SonaRewardToken_TokenIdDoesNotExist.selector
		);

		rewardToken.tokenURI(99);
	}

	function xtest_UpdateRewardTokenMetadata() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";

		rewardToken.mint(rewardTokenRecipient, _tokenId, cid, zeroSplitsAddr);
		rewardToken.updateArweaveTxId(_tokenId, "Qmabcdefghijklmnopqrstud");

		assertEq(rewardToken.tokenURI(_tokenId), "ar://Qmabcdefghijklmnopqrstud");
	}

	function test_MintSucceeds() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";

		vm.expectEmit(true, false, false, true, address(rewardToken));
		emit RewardTokenMetadataUpdated(_tokenId, cid, payoutAddr);

		rewardToken.mint(rewardTokenRecipient, _tokenId, cid, payoutAddr);

		ISonaRewardToken.RewardToken memory collectorData = rewardToken
			.getRewardTokenMetadata(_tokenId);
		assertEq(collectorData.arTxId, cid);
		assertEq(collectorData.payout, payoutAddr);

		string memory uri = rewardToken.tokenURI(_tokenId);
		assertEq(
			uri,
			"http://fakeSona.stream/31337/0x34a1d3fff3958843c43ad80f30b94c510645c316000000000000000000000003/nft-metadata.json"
		);
	}

	function test_getArtistEdition() public {
		vm.expectRevert("TokenId: Already Artist Edition");
		_artistTokenId.getArtistEdition();
	}

	function test_MintMultipleToArtistSucceeds() public {
		ISonaRewardToken.TokenMetadata memory bundle0 = ISonaRewardToken
			.TokenMetadata({
				tokenId: (0x25 << 96) | 1,
				payout: payable(address(0)),
				metadataId: "cool NFT"
			});
		ISonaRewardToken.TokenMetadata memory bundle1 = ISonaRewardToken
			.TokenMetadata({
				tokenId: (0x25 << 96) | 2,
				payout: payable(address(0)),
				metadataId: "cool NFTs"
			});
		ISonaRewardToken.TokenMetadata[]
			memory bundles = new ISonaRewardToken.TokenMetadata[](2);
		bundles[0] = bundle0;
		bundles[1] = bundle1;

		rewardToken.mintMultipleToArtist(bundles);

		ISonaRewardToken.RewardToken memory collectorData = rewardToken
			.getRewardTokenMetadata((0x25 << 96) | 1);
		assertEq(collectorData.arTxId, bundle0.metadataId);
		assertEq(collectorData.payout, bundle0.payout);

		collectorData = rewardToken.getRewardTokenMetadata((0x25 << 96) | 2);
		assertEq(collectorData.arTxId, bundle1.metadataId);
		assertEq(collectorData.payout, bundle1.payout);
	}

	function test_updatePayoutAddress() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";

		rewardToken.mint(rewardTokenRecipient, _tokenId, cid, zeroSplitsAddr);

		vm.expectEmit(true, false, false, true, address(rewardToken));
		emit PayoutAddressUpdated(_tokenId, payable(address(1)));
		vm.prank(rewardTokenRecipient);
		rewardToken.updatePayoutAddress(_tokenId, payable(address(1)));

		address payable result = rewardToken.getRewardTokenPayoutAddr(_tokenId);
		assertEq(result, payable(address(1)));

		vm.expectRevert(ISonaRewardToken.SonaRewardToken_Unauthorized.selector);
		rewardToken.updatePayoutAddress(_tokenId, payable(rewardTokenRecipient));
	}

	function test_updateBlockListAddress() public {
		mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 18223529);
		setUp();
		vm.prank(tokenAdmin);
		rewardToken.updateBlockListAddress(
			0x4fC5Da4607934cC80A0C6257B1F36909C58dD622
		);

		// can set approval for reservoir
		address reservoir = 0xC2c862322E9c97D6244a3506655DA95F05246Fd8;
		rewardToken.setApprovalForAll(reservoir, true);

		// cannot set approval for seaport v1.5
		address seaport = 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC;
		vm.expectRevert(
			abi.encodeWithSelector(
				SonaRewardToken_OperatorNotAllowed.selector,
				seaport
			)
		);
		rewardToken.setApprovalForAll(seaport, true);
	}

	function test_optimismTokenBridge() public {
		mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 18223529);
		setUp();
		IERC721Bridge bridge = IERC721Bridge(
			0x5a7749f83b81B301cAb5f48EB8516B986DAef23D
		);
		rewardToken.mint(rewardTokenRecipient, _tokenId, "derp", payoutAddr);
		uint256[] memory tokenIds = new uint256[](1);
		tokenIds[0] = _tokenId;

		vm.expectEmit(true, true, true, true, address(bridge));
		emit ERC721BridgeInitiated(
			address(rewardToken),
			address(rewardToken),
			address(rewardToken),
			rewardTokenRecipient,
			_tokenId,
			""
		);
		hoax(rewardTokenRecipient);
		rewardToken.migratetoL2(tokenIds, bridge);
	}

	function test_contractURI() public {
		string memory result = rewardToken.contractURI();
		assertEq(result, "http://fakeSona.stream/31337/contract-metadata.json");
	}
}
