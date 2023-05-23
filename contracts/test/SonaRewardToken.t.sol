// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

//  ___  _____  _  _    __      ___  ____  ____  ____    __    __  __
// / __)(  _  )( \( )  /__\    / __)(_  _)(  _ \( ___)  /__\  (  \/  )
// \__ \ )(_)(  )  (  /(__)\   \__ \  )(   )   / )__)  /(__)\  )    (
// (___/(_____)(_)\_)(__)(__)  (___/ (__) (_)\_)(____)(__)(__)(_/\/\_)

import { SonaRewardToken, AddressableTokenId } from "../SonaRewardToken.sol";
import { SonaReserveAuction } from "../SonaReserveAuction.sol";
import { IERC721AUpgradeable } from "erc721a-upgradeable/IERC721AUpgradeable.sol";
import { ERC721Holder } from "openzeppelin/token/ERC721/utils/ERC721Holder.sol";
import { ISonaRewardToken } from "../interfaces/ISonaRewardToken.sol";
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
	address public auctionInitializer = makeAddr("auctionInitializer");

	address payable public zeroSplitsAddr = payable(address(0));
	address payable public payoutAddr = payable(makeAddr("splitAddress"));

	uint256 private _tokenId = (uint256(uint160(address(this))) << 96) | 3;
	uint256 private _artistTokenId = (uint256(uint160(address(this))) << 96) | 2;

	SonaRewardToken public rewardToken;

	function setUp() public {
		SonaRewardToken rewardTokenBase = new SonaRewardToken();
		vm.prank(auctionInitializer);
		ERC1967Proxy proxy = new ERC1967Proxy(
			address(rewardTokenBase),
			abi.encodeWithSelector(
				SonaRewardToken.initialize.selector,
				"SonaRewardToken",
				"SRT",
				address(0),
				address(this)
			)
		);
		rewardToken = SonaRewardToken(address(proxy));
	}

	function test_UnauthorizedMintReverts(address badMinter) public {
		vm.assume(badMinter != auctionInitializer);
		vm.assume(badMinter != address(this));

		vm.prank(badMinter);
		vm.expectRevert();
		rewardToken.mintFromAuction(
			_tokenId,
			address(this),
			rewardTokenRecipient,
			"",
			"",
			zeroSplitsAddr
		);
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

	function test_UpdateRewardTokenMetadata() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(
			_tokenId,
			address(this),
			rewardTokenRecipient,
			cid,
			cid2,
			zeroSplitsAddr
		);
		rewardToken.updateArweaveTxId(_tokenId, "Qmabcdefghijklmnopqrstud");

		assertEq(rewardToken.tokenURI(_tokenId), "ar://Qmabcdefghijklmnopqrstud");
	}

	function test_BurnCreatorRewardToken() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(
			_tokenId,
			address(this),
			rewardTokenRecipient,
			cid,
			cid2,
			zeroSplitsAddr
		);

		rewardToken.burnRewardToken(_artistTokenId);

		vm.expectRevert("NOT_MINTED");
		rewardToken.ownerOf(_artistTokenId);
	}

	function test_BurnCollectorRewardToken() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(
			_tokenId,
			address(this),
			rewardTokenRecipient,
			cid,
			cid2,
			zeroSplitsAddr
		);

		vm.prank(rewardTokenRecipient);
		rewardToken.burnRewardToken(_tokenId);

		vm.expectRevert("NOT_MINTED");
		rewardToken.ownerOf(_tokenId);
	}

	function test_CreatorBurnCollectorTokenFails() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(
			_tokenId,
			address(this),
			rewardTokenRecipient,
			cid,
			cid2,
			zeroSplitsAddr
		);

		vm.expectRevert(ISonaRewardToken.SonaRewardToken_Unauthorized.selector);
		rewardToken.burnRewardToken(_tokenId);
	}

	function testFuzz_randomBurnerFails(
		address _artistBurner,
		address _collectorBurner
	) public {
		vm.assume(_artistBurner != address(this));
		vm.assume(_collectorBurner != rewardTokenRecipient);

		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(
			_tokenId,
			address(this),
			rewardTokenRecipient,
			cid,
			cid2,
			zeroSplitsAddr
		);

		vm.prank(_artistBurner);
		vm.expectRevert(ISonaRewardToken.SonaRewardToken_Unauthorized.selector);
		rewardToken.burnRewardToken(_artistTokenId);

		vm.prank(_collectorBurner);
		vm.expectRevert(ISonaRewardToken.SonaRewardToken_Unauthorized.selector);
		rewardToken.burnRewardToken(_tokenId);
	}

	function test_MintSucceeds() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(
			_tokenId,
			address(this),
			rewardTokenRecipient,
			cid,
			cid2,
			payoutAddr
		);
		ISonaRewardToken.RewardToken memory collectorData = rewardToken
			.getRewardTokenMetadata(_tokenId);
		assertEq(collectorData.arTxId, cid2);
		assertEq(collectorData.payout, address(0));
		ISonaRewardToken.RewardToken memory artistData = rewardToken
			.getRewardTokenMetadata(_artistTokenId);
		assertEq(artistData.arTxId, cid);
		assertEq(artistData.payout, payoutAddr);

		vm.expectRevert("TokenId: Already Artist Edition");
		_artistTokenId.getArtistEdition();
	}

	function test_MintFails() public {
		vm.expectRevert(
			ISonaRewardToken.SonaRewardToken_ArtistEditionEven.selector
		);
		rewardToken.mintFromAuction(
			_artistTokenId,
			address(this),
			rewardTokenRecipient,
			"",
			"",
			zeroSplitsAddr
		);

		uint256 bad_artistTokenId = (uint256(uint160(makeAddr("badMinter"))) <<
			96) | 3;
		vm.expectRevert(
			ISonaRewardToken.SonaRewardToken_NoArtistInTokenId.selector
		);
		rewardToken.mintFromAuction(
			bad_artistTokenId,
			address(this),
			rewardTokenRecipient,
			"",
			"",
			zeroSplitsAddr
		);
	}

	function test_updatePayoutAddress() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(
			_tokenId,
			address(this),
			rewardTokenRecipient,
			cid,
			cid2,
			payoutAddr
		);

		vm.expectEmit(true, false, false, true, address(rewardToken));
		emit PayoutAddressUpdated(_artistTokenId, address(1));
		rewardToken.updatePayoutAddress(_artistTokenId, payable(address(1)));

		address payable result = rewardToken.getRewardTokenPayoutAddr(
			_artistTokenId
		);
		assertEq(result, payable(address(1)));

		vm.prank(rewardTokenRecipient);
		vm.expectRevert(ISonaRewardToken.SonaRewardToken_Unauthorized.selector);
		rewardToken.updatePayoutAddress(
			_artistTokenId,
			payable(rewardTokenRecipient)
		);

		vm.prank(rewardTokenRecipient);
		vm.expectRevert(ISonaRewardToken.SonaRewardToken_ArtistEditionOdd.selector);
		rewardToken.updatePayoutAddress(_tokenId, payable(address(1)));
	}
}
