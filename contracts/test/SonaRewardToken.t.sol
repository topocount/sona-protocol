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

contract SonaRewardTokenTest is Util, ERC721Holder {
	using AddressableTokenId for uint256;
	// treasury address getting the fees
	address public treasuryRecipient = makeAddr("treasuryRecipient");
	// redistribution address getting the fees
	address public redistributionRecipient = makeAddr("redistributionRecipient");
	// reward token recipient
	address public rewardTokenRecipient = makeAddr("rewardTokenRecipient");
	// auction mock
	address public auctionInitializer = makeAddr("auctionInitializer");

	uint256 private _tokenId = (uint256(uint160(address(this))) << 96) | 3;
	uint256 private _artistTokenId = (uint256(uint160(address(this))) << 96) | 2;

	SonaRewardToken public rewardToken;

	function setUp() public {
		SonaRewardToken rewardTokenBase = new SonaRewardToken();
		vm.prank(auctionInitializer);
		ERC1967Proxy proxy = new ERC1967Proxy(address(rewardTokenBase), abi.encodeWithSelector(SonaRewardToken.initialize.selector, "SonaRewardToken", "SRT", address(0), address(this)));
		rewardToken = SonaRewardToken(address(proxy));
	}

	function test_UnauthorizedMintReverts(address badMinter) public {
		vm.assume(badMinter != auctionInitializer);
		vm.assume(badMinter != address(this));

		vm.prank(badMinter);
		vm.expectRevert();
		rewardToken.mintFromAuction(_tokenId, address(this), rewardTokenRecipient, "", "");
	}

	function test_initializedParams() public {
		rewardToken.name;
		assertEq(rewardToken.name(), "SonaRewardToken");
		assertEq(rewardToken.symbol(), "SRT");
	}

	function test_InvalidTokenIDOnTokenURIExistsReverts() public {
		vm.expectRevert(ISonaRewardToken.SonaRewardToken_TokenIdDoesNotExist.selector);

		rewardToken.tokenURI(99);
	}

	function test_UpdateRewardTokenCID() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(_tokenId, address(this), rewardTokenRecipient, cid, cid2);
		rewardToken.updateArweaveTxId(_tokenId, "Qmabcdefghijklmnopqrstud");

		assertEq(rewardToken.tokenURI(_tokenId), "ar://Qmabcdefghijklmnopqrstud");
	}

	function test_BurnCreatorRewardToken() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(_tokenId, address(this), rewardTokenRecipient, cid, cid2);

		rewardToken.burnRewardToken(_artistTokenId);

		vm.expectRevert("NOT_MINTED");
		rewardToken.ownerOf(_artistTokenId);
	}

	function test_BurnCollectorRewardToken() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(_tokenId, address(this), rewardTokenRecipient, cid, cid2);

		vm.prank(rewardTokenRecipient);
		rewardToken.burnRewardToken(_tokenId);

		vm.expectRevert("NOT_MINTED");
		rewardToken.ownerOf(_tokenId);
	}

	function test_CreatorBurnCollectorTokenFails() public {
		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(_tokenId, address(this), rewardTokenRecipient, cid, cid2);

		vm.expectRevert(ISonaRewardToken.SonaRewardToken_Unauthorized.selector);
		rewardToken.burnRewardToken(_tokenId);
	}

	function testFuzz_randomBurnerFails(address _artistBurner, address _collectorBurner) public {
		vm.assume(_artistBurner != address(this));
		vm.assume(_collectorBurner != rewardTokenRecipient);

		string memory cid = "Qmabcdefghijklmnopqrstuv";
		string memory cid2 = "Qmabcdefghijklmnopqrstuvx";

		rewardToken.mintFromAuction(_tokenId, address(this), rewardTokenRecipient, cid, cid2);

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

		rewardToken.mintFromAuction(_tokenId, address(this), rewardTokenRecipient, cid, cid2);
		string memory arId = rewardToken.getRewardTokenArweaveId(_tokenId);
		assertEq(arId, cid2);
		string memory artistArId = rewardToken.getRewardTokenArweaveId(_artistTokenId);
		assertEq(artistArId, cid);

		vm.expectRevert("TokenId: Already Artist Edition");
		_artistTokenId.getArtistEdition();
	}

	function test_MintFails() public {
		vm.expectRevert(ISonaRewardToken.SonaRewardToken_ArtistEditionEven.selector);
		rewardToken.mintFromAuction(_artistTokenId, address(this), rewardTokenRecipient, "", "");

		uint256 bad_artistTokenId = (uint256(uint160(makeAddr("badMinter"))) << 96) | 3;
		vm.expectRevert(ISonaRewardToken.SonaRewardToken_NoArtistInTokenId.selector);
		rewardToken.mintFromAuction(bad_artistTokenId, address(this), rewardTokenRecipient, "", "");
	}
}
