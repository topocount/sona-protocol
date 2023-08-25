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
		rewardToken.mint(rewardTokenRecipient, _tokenId, "", zeroSplitsAddr);

		ISonaRewardToken.TokenMetadata memory bundle = ISonaRewardToken
			.TokenMetadata({
				tokenId: 12345,
				payout: payable(address(0)),
				arweaveTxId: "cool NFT"
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

	function test_UpdateRewardTokenMetadata() public {
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

		vm.expectRevert("TokenId: Already Artist Edition");
		_artistTokenId.getArtistEdition();
	}

	function test_MintMultipleToArtistSucceeds() public {
		ISonaRewardToken.TokenMetadata memory bundle0 = ISonaRewardToken
			.TokenMetadata({
				tokenId: (0x25 << 96) | 1,
				payout: payable(address(0)),
				arweaveTxId: "cool NFT"
			});
		ISonaRewardToken.TokenMetadata memory bundle1 = ISonaRewardToken
			.TokenMetadata({
				tokenId: (0x25 << 96) | 2,
				payout: payable(address(0)),
				arweaveTxId: "cool NFTs"
			});
		ISonaRewardToken.TokenMetadata[]
			memory bundles = new ISonaRewardToken.TokenMetadata[](2);
		bundles[0] = bundle0;
		bundles[1] = bundle1;

		rewardToken.mintMultipleToArtist(bundles);

		ISonaRewardToken.RewardToken memory collectorData = rewardToken
			.getRewardTokenMetadata((0x25 << 96) | 1);
		assertEq(collectorData.arTxId, bundle0.arweaveTxId);
		assertEq(collectorData.payout, bundle0.payout);

		collectorData = rewardToken.getRewardTokenMetadata((0x25 << 96) | 2);
		assertEq(collectorData.arTxId, bundle1.arweaveTxId);
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
}
