// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { SonaReserveAuction } from "../SonaReserveAuction.sol";
import { SonaRewardToken, ISonaRewardToken } from "../SonaRewardToken.sol";
import { ISonaReserveAuction } from "../interfaces/ISonaReserveAuction.sol";
import { ISonaAuthorizer } from "../interfaces/ISonaAuthorizer.sol";
import { ISplitMain } from "../payout/interfaces/ISplitMain.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { Util } from "./Util.sol";
import { SplitHelpers } from "./util/SplitHelpers.t.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { Weth9Mock, IWETH } from "./mock/Weth9Mock.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { ERC20ReturnTrueMock, ERC20NoReturnMock, ERC20ReturnFalseMock } from "./mock/ERC20Mock.sol";
import { ContractBidderMock } from "./mock/ContractBidderMock.sol";
import { Weth9Mock, IWETH } from "./mock/Weth9Mock.sol";
import { SplitMain } from "../payout/SplitMain.sol";

/* solhint-disable max-states-count */
contract SonaReserveAuctionTest is Util, SonaReserveAuction, SplitHelpers {
	event RewardTokenMetadataUpdated(
		uint256 indexed tokenId,
		string txId,
		address payout
	);

	SonaReserveAuction public auction;

	// treasury address getting the fees
	address public treasuryRecipient = makeAddr("treasuryRecipient");
	// redistribution address getting the fees
	address public redistributionRecipient = makeAddr("redistributionRecipient");
	// wallet who minted the tracks
	address public trackMinter = makeAddr("trackMinter");
	// wallet who initiated the contracts
	address public rootOwner = makeAddr("rootOwner");
	// wallet who is the bidder
	address public bidder = makeAddr("bidder");
	// wallet who is the second bidder
	address public secondBidder = makeAddr("secondBidder");
	// address for non-eth token
	address public nonEthToken = makeAddr("nonEthToken");
	// derived from ../../scripts/signTyped.ts
	address payable public artistPayout = payable(address(25));
	address payable public zeroPayout = payable(address(0));

	uint256 public tokenId = (uint256(uint160(trackMinter)) << 96) | 69;

	// Weth
	Weth9Mock public mockWeth = new Weth9Mock();

	// Contract bidder
	ContractBidderMock public contractBidder;

	function setUp() public {
		splitMainImpl = new SplitMain(authorizer);
		vm.startPrank(rootOwner);
		// WARNING: deployment order matters for the signatures below
		SonaRewardToken rewardTokenBase = new SonaRewardToken();
		SonaReserveAuction auctionBase = new SonaReserveAuction();
		ERC1967Proxy proxy = new ERC1967Proxy(
			address(auctionBase),
			abi.encodeWithSelector(
				SonaReserveAuction.initialize.selector,
				treasuryRecipient,
				redistributionRecipient,
				authorizer,
				rewardTokenBase,
				splitMainImpl,
				address(0),
				mockWeth
			)
		);
		auction = SonaReserveAuction(address(proxy));
		contractBidder = new ContractBidderMock(auction);
		vm.stopPrank();
	}

	function test_revertsWithInvalidAddress() public {
		SonaRewardToken rewardTokenBase = new SonaRewardToken();
		SonaReserveAuction auctionBase = new SonaReserveAuction();
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidAddress.selector
		);
		new ERC1967Proxy(
			address(auctionBase),
			abi.encodeWithSelector(
				SonaReserveAuction.initialize.selector,
				address(0),
				redistributionRecipient,
				authorizer,
				rewardTokenBase,
				address(0),
				address(0),
				mockWeth
			)
		);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidAddress.selector
		);
		new ERC1967Proxy(
			address(auctionBase),
			abi.encodeWithSelector(
				SonaReserveAuction.initialize.selector,
				treasuryRecipient,
				address(0),
				authorizer,
				rewardTokenBase,
				address(0),
				address(0),
				mockWeth
			)
		);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidAddress.selector
		);
		new ERC1967Proxy(
			address(auctionBase),
			abi.encodeWithSelector(
				SonaReserveAuction.initialize.selector,
				treasuryRecipient,
				redistributionRecipient,
				address(0),
				rewardTokenBase,
				address(0),
				address(0),
				mockWeth
			)
		);

		vm.expectRevert("ERC1967: new implementation is not a contract");
		new ERC1967Proxy(
			address(auctionBase),
			abi.encodeWithSelector(
				SonaReserveAuction.initialize.selector,
				treasuryRecipient,
				redistributionRecipient,
				authorizer,
				address(0),
				address(0),
				address(0),
				mockWeth
			)
		);
	}

	function _createSignedBundles()
		private
		view
		returns (MetadataBundle[2] memory bundles, Signature[2] memory signatures)
	{
		Signature memory artistSignature = Signature(
			27,
			0xc52d5322b2123504e8fa2d4f4201864a8963f1cee34089ef658178ee98a2931c,
			0x5f78ab90cb573c3150b5828a36abee18447db2a918723948a9bef235d6dec314
		);
		Signature memory collectorSignature = Signature(
			27,
			0x15208b7948eca71121fcdee28001f81036ca7331f48f474be538f0d80c719863,
			0x7f9a2d05566a9c9eb52b21a7159c61dd8fc650fec20df551a3024eeafd72c2d1
		);

		bundles = _createBundles();
		signatures = [artistSignature, collectorSignature];
	}

	function _createBundles()
		private
		view
		returns (MetadataBundle[2] memory bundles)
	{
		MetadataBundle memory artistBundle = MetadataBundle({
			arweaveTxId: "Hello World!",
			tokenId: 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000044,
			payout: artistPayout,
			rewardsPayout: zeroPayout
		});
		MetadataBundle memory collectorBundle = MetadataBundle({
			arweaveTxId: "Hello World",
			tokenId: 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000045,
			payout: payable(address(0)),
			rewardsPayout: zeroPayout
		});

		bundles = [artistBundle, collectorBundle];
	}

	function _signBundle(
		MetadataBundle memory _bundle
	) private view returns (Signature memory signature) {
		bytes32 bundleHash = _getBundleHash(_bundle);
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, bundleHash);

		return Signature({ v: v, r: r, s: s });
	}

	function _getBundleSignatures(
		MetadataBundle[2] memory _bundles
	) private view returns (Signature[2] memory signatures) {
		signatures[0] = _signBundle(_bundles[0]);
		signatures[1] = _signBundle(_bundles[1]);
	}

	function test_CreateReserveAuction() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
		vm.stopPrank();

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.reservePrice, 1 ether);
		assertEq(auctionData.trackSeller, trackMinter);
		assertEq(auctionData.currentBidAmount, 0);
		assertEq(auctionData.currentBidder, address(0));
		assertEq(auctionData.currency, address(0));
		assertEq(auctionData.bundles[0].arweaveTxId, bundles[0].arweaveTxId);
		assertEq(auctionData.bundles[0].tokenId, bundles[0].tokenId);
		assertEq(auctionData.bundles[1].arweaveTxId, bundles[1].arweaveTxId);
		assertEq(auctionData.bundles[1].tokenId, bundles[1].tokenId);
	}

	function test_CreateReserveAuctionMultipleReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_AlreadyListed.selector
		);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
		vm.stopPrank();
	}

	function test_CreateReserveAuctionZeroReserveReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.startPrank(trackMinter);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_ReservePriceCannotBeZero.selector
		);
		auction.createReserveAuction(bundles, signatures, address(0), 0);
		vm.stopPrank();
	}

	function test_CreateReserveAuctionWithInvalidArtistBundleReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		signatures[0].v = 69;

		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaAuthorizer.SonaAuthorizer_InvalidSignature.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateReserveAuctionWithInvalidCollectorBundleReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		signatures[1].v = 69;

		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaAuthorizer.SonaAuthorizer_InvalidSignature.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateReserveAuctionWithInvalidArtistTokenIdReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		bundles[0].tokenId = (uint256(uint160(trackMinter)) << 96) | 69;

		signatures[0] = _signBundle(bundles[0]);

		vm.startPrank(trackMinter);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidTokenIds.selector
		);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateReserveAuctionWithInvalidCollectorTokenIdReverts()
		public
	{
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		bundles[1].tokenId = (uint256(uint160(trackMinter)) << 96) | 70;

		signatures[1] = _signBundle(bundles[1]);

		vm.startPrank(trackMinter);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidTokenIds.selector
		);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateReserveAuctionWithInvalidCallerReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.startPrank(address(0xcccccc));

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector
		);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateBid() public {
		MetadataBundle[2] memory bundles = _createBundles();
		Signature[2] memory signatures = _getBundleSignatures(bundles);
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.currentBidAmount, 1.1 ether);
		assertEq(auctionData.currentBidder, bidder);
	}

	function test_CreateBidWithInvalidAuctionReverts() public {
		hoax(bidder);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidAuction.selector
		);
		auction.createBid{ value: 1.1 ether }(88, 0);
	}

	function test_CreateBidWithZeroBidReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_BidTooLow.selector);
		auction.createBid{ value: 0.0 ether }(tokenId, 0);
	}

	function test_CreateBidWithLowBidReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_BidTooLow.selector);
		auction.createBid{ value: 0.9 ether }(tokenId, 0);
	}

	function test_CreateBidWithSameBidder() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);
		auction.createBid{ value: 1.2 ether }(tokenId, 0);
	}

	function test_CreateLowBidWithSameBidderReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);
		vm.expectRevert(SonaReserveAuction_BidTooLow.selector);
		auction.createBid{ value: 1.0 ether }(tokenId, 0);
	}

	function test_CreateMultipleBidsReturnsOriginalERC20BidderFunds() public {
		ERC20ReturnTrueMock mockERC20 = new ERC20ReturnTrueMock();
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(mockERC20), 10);

		deal(address(mockERC20), bidder, 100);
		vm.prank(bidder);
		auction.createBid(tokenId, 100);

		hoax(secondBidder);
		auction.createBid(tokenId, 110);

		assertEq(IERC20(address(mockERC20)).balanceOf(bidder), 100);
	}

	function test_CreateMultipleBidsReturnsOriginalETHEOABidderFundsWithEth()
		public
	{
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder, 1.1 ether);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		hoax(secondBidder);
		auction.createBid{ value: 2 ether }(tokenId, 0);

		assertEq(address(bidder).balance, 1.1 ether);
	}

	function test_CreateBidWithOnExpiredAuctionReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		auction.createBid{ value: 1.1 ether }(tokenId, 0);
		vm.warp(2 days);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_AuctionEnded.selector
		);
		auction.createBid{ value: 1.2 ether }(tokenId, 0);
	}

	function test_CancelAuction() public {
		vm.startPrank(trackMinter);

		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
		auction.cancelReserveAuction(tokenId);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(0);

		assertEq(auctionData.trackSeller, address(0));
		assertEq(auctionData.reservePrice, 0);
	}

	function test_UpdateReserveAuctionPriceWithZeroReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_ReservePriceCannotBeZero.selector
		);
		auction.updateReserveAuctionPrice(tokenId, 0);
	}

	function test_UpdateReserveAuctionPrice() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		auction.updateReserveAuctionPrice(tokenId, 2 ether);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.reservePrice, 2 ether);
	}

	function test_UpdateReserveAuctionPriceAuctionAlreadyLive() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.startPrank(trackMinter);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_AuctionIsLive.selector
		);
		auction.updateReserveAuctionPrice(tokenId, 2 ether);
	}

	function test_UpdateReserveAuctionPriceWithInvalidCallerReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.startPrank(makeAddr("unauthorizedUser"));

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector
		);
		auction.updateReserveAuctionPrice(tokenId, 2 ether);
	}

	function test_CreateDuplicateFailsAfterSettlement() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		vm.prank(trackMinter);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_Duplicate.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_SettleReserveAuctionWithrewardsPayoutSet() public {
		address payable rewardsPayout = payable(makeAddr("rewardsPayout"));
		MetadataBundle[2] memory bundles = _createBundles();
		bundles[0].rewardsPayout = rewardsPayout;
		Signature[2] memory signatures = _getBundleSignatures(bundles);
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.prank(trackMinter);
		vm.expectEmit(true, false, false, false, address(auction));
		emit ReserveAuctionSettled({ tokenId: tokenId });
		auction.settleReserveAuction(tokenId);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.trackSeller, address(0));
		assertEq(auctionData.reservePrice, 0);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(trackMinter), 1);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(tokenId - 1),
			trackMinter
		);
		assertEq(ERC721(address(auction.rewardToken())).ownerOf(tokenId), bidder);

		ISonaRewardToken token = auction.rewardToken();

		ISonaRewardToken.RewardToken memory metadata = token.getRewardTokenMetadata(
			tokenId - 1
		);
		assertEq(metadata.payout, rewardsPayout);

		metadata = token.getRewardTokenMetadata(tokenId);
		assertEq(metadata.payout, address(0));
	}

	function test_SettleReserveAuction() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.startPrank(trackMinter);
		vm.expectEmit(true, false, false, false, address(auction));
		emit ReserveAuctionSettled(tokenId);
		auction.settleReserveAuction(tokenId);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.trackSeller, address(0));
		assertEq(auctionData.reservePrice, 0);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(trackMinter), 1);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(tokenId - 1),
			trackMinter
		);
		assertEq(ERC721(address(auction.rewardToken())).ownerOf(tokenId), bidder);

		ISonaRewardToken token = auction.rewardToken();

		ISonaRewardToken.RewardToken memory metadata = token.getRewardTokenMetadata(
			tokenId - 1
		);
		assertEq(metadata.payout, address(0));
		metadata = token.getRewardTokenMetadata(tokenId);
		assertEq(metadata.payout, address(0));
	}

	function test_DistributeERC20ToSplit() public {
		ERC20ReturnTrueMock mockERC20 = new ERC20ReturnTrueMock();
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		MetadataBundle[2] memory bundles = _createBundles();
		bundles[0].payout = split;
		Signature[2] memory signatures = _getBundleSignatures(bundles);
		vm.prank(trackMinter);
		auction.createReserveAuction(
			bundles,
			signatures,
			address(mockERC20),
			1 ether
		);

		uint256 bidAmount = 1.1 ether;

		hoax(bidder);
		auction.createBid(tokenId, bidAmount);

		vm.warp(2 days);

		uint initialBalance0 = mockERC20.balanceOf(accounts[0]);
		uint initialBalance1 = mockERC20.balanceOf(accounts[1]);

		vm.prank(trackMinter);
		auction.settleReserveAuctionAndDistributePayout(tokenId, accounts, amounts);

		uint finalBalance0 = mockERC20.balanceOf(accounts[0]);
		uint finalBalance1 = mockERC20.balanceOf(accounts[1]);

		assertEq(finalBalance0 - initialBalance0, 511500000000000000 - 1);
		assertEq(finalBalance1 - initialBalance1, 511500000000000000 - 1);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.trackSeller, address(0));
		assertEq(auctionData.reservePrice, 0);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(trackMinter), 1);
	}

	function test_DistributeETHToSplit() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		MetadataBundle[2] memory bundles = _createBundles();
		bundles[0].payout = split;
		Signature[2] memory signatures = _getBundleSignatures(bundles);
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.warp(2 days);

		uint initialBalance0 = accounts[0].balance;
		uint initialBalance1 = accounts[1].balance;

		vm.prank(trackMinter);
		auction.settleReserveAuctionAndDistributePayout(tokenId, accounts, amounts);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		uint finalBalance0 = accounts[0].balance;
		uint finalBalance1 = accounts[1].balance;

		assertEq(finalBalance0 - initialBalance0, 511500000000000000);
		assertEq(finalBalance1 - initialBalance1, 511500000000000000);

		assertEq(auctionData.trackSeller, address(0));
		assertEq(auctionData.reservePrice, 0);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(trackMinter), 1);
	}

	function test_SettleReserveAuctionWhileLiveReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.prank(trackMinter);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_AuctionIsLive.selector
		);
		auction.settleReserveAuction(tokenId);
	}

	function test_SettleReserveAuctionInvalidCallerReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector
		);
		auction.settleReserveAuction(tokenId);
	}

	function test_CancelInvalidReserveAuctionReverts() public {
		vm.startPrank(trackMinter);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidAuction.selector
		);
		auction.cancelReserveAuction(tokenId);
	}

	function test_CancelReserveAuctionInvalidCallerReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.startPrank(makeAddr("unauthorizedUser"));

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector
		);
		auction.cancelReserveAuction(0);
	}

	function test_CancelReserveAuctionStillLiveReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.startPrank(trackMinter);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_AuctionIsLive.selector
		);
		auction.cancelReserveAuction(tokenId);
	}

	function test_CreateReserveAuctionWithERC20Currency() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, nonEthToken, 10000);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.reservePrice, 10000);
		assertEq(auctionData.trackSeller, trackMinter);
		assertEq(auctionData.currency, nonEthToken);

		vm.stopPrank();
	}

	function test_CreateBidERC20() public {
		ERC20ReturnTrueMock mockRewardToken = new ERC20ReturnTrueMock();
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(
			bundles,
			signatures,
			address(mockRewardToken),
			10000
		);

		hoax(bidder);
		auction.createBid(tokenId, 10000);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.currentBidAmount, 10000);
		assertEq(auctionData.currentBidder, bidder);

		hoax(bidder);
		auction.createBid(tokenId, 50000);

		auctionData = auction.getAuction(tokenId);

		assertEq(auctionData.currentBidAmount, 50000);
		assertEq(auctionData.currentBidder, bidder);
	}

	function test_CreateBidWithBrokenERC20Reverts() public {
		ERC20NoReturnMock brokenMockRewardToken = new ERC20NoReturnMock();
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(
			bundles,
			signatures,
			address(brokenMockRewardToken),
			10000
		);

		hoax(bidder);
		vm.expectRevert(bytes(""));
		auction.createBid(tokenId, 10000);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.currentBidAmount, 0);
		assertEq(auctionData.currentBidder, address(0));
	}

	function test_CreateBidWithInvalidERC20PermissionsReverts() public {
		ERC20ReturnFalseMock mockRewardToken = new ERC20ReturnFalseMock();
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(
			bundles,
			signatures,
			address(mockRewardToken),
			10000
		);

		hoax(bidder);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_TransferFailed.selector
		);
		auction.createBid(tokenId, 10000);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.currentBidAmount, 0);
		assertEq(auctionData.currentBidder, address(0));
	}

	function test_CreateBidERC20WithEthReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, nonEthToken, 10000);

		hoax(bidder);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidCurrency.selector
		);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.currentBidAmount, 0);
		assertEq(auctionData.currentBidder, address(0));
	}

	function test_UpdateReserveAuctionPayoutAddress() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.bundles[0].payout, artistPayout);

		address payable newPayout = payable(address(26));

		vm.prank(trackMinter);
		auction.updateArtistPayoutAddress(tokenId, newPayout);

		ISonaReserveAuction.Auction memory newAuctionData = auction.getAuction(
			tokenId
		);

		assertEq(newAuctionData.bundles[0].payout, newPayout);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		newPayout = payable(address(27));

		vm.prank(trackMinter);
		vm.expectEmit(true, false, false, true, address(auction));
		emit PayoutAddressUpdated(tokenId, newPayout);
		auction.updateArtistPayoutAddress(tokenId, newPayout);

		newAuctionData = auction.getAuction(tokenId);

		assertEq(newAuctionData.bundles[0].payout, newPayout);
	}

	function test_InvalidUpdateReserveAuctionPayoutAddress() public {
		address payable newPayout = payable(address(26));
		// cannot be updated before auction is created
		vm.prank(trackMinter);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidAuction.selector
		);
		auction.updateArtistPayoutAddress(tokenId, newPayout);

		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.bundles[0].payout, artistPayout);

		// cannot be updated by non-minter
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector
		);
		auction.updateArtistPayoutAddress(tokenId, newPayout);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		// cannot be updated after auction is settled
		vm.prank(trackMinter);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidAuction.selector
		);
		auction.updateArtistPayoutAddress(tokenId, newPayout);
	}

	function test_UpdateReserveAuctionPriceAndCurrency() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.reservePrice, 1 ether);
		assertEq(auctionData.trackSeller, trackMinter);
		assertEq(auctionData.currency, address(0));

		vm.prank(trackMinter);
		auction.updateReserveAuctionPriceAndCurrency(nonEthToken, tokenId, 100000);

		ISonaReserveAuction.Auction memory newAuctionData = auction.getAuction(
			tokenId
		);

		assertEq(newAuctionData.reservePrice, 100000);
		assertEq(newAuctionData.trackSeller, trackMinter);
		assertEq(newAuctionData.currency, nonEthToken);
	}

	function test_UpdateReserveAuctionPriceAndCurrencyAuctionZeroPriceReverts()
		public
	{
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.startPrank(trackMinter);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_ReservePriceCannotBeZero.selector
		);
		auction.updateReserveAuctionPriceAndCurrency(nonEthToken, tokenId, 0);
	}

	function test_UpdateReserveAuctionPriceAndCurrencyAuctionAlreadyLive()
		public
	{
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.startPrank(trackMinter);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_AuctionIsLive.selector
		);
		auction.updateReserveAuctionPriceAndCurrency(nonEthToken, tokenId, 100000);
	}

	function test_UpdateReserveAuctionPriceAndCurrencyWithInvalidCallerReverts()
		public
	{
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.startPrank(makeAddr("unauthorizedUser"));

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector
		);
		auction.updateReserveAuctionPriceAndCurrency(nonEthToken, tokenId, 100000);
	}

	function testFuzz_SettleReserveAuctionSendsEthFundsToSplits(
		uint256 _reservePrice,
		uint256 _bidAmount
	) public {
		vm.deal(bidder, _bidAmount);
		vm.assume(_bidAmount < 2_000_000_000_000 ether);
		vm.assume(_reservePrice > 0);
		vm.assume(_bidAmount >= _reservePrice);
		vm.assume(_bidAmount < type(uint256).max / 5000);
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(
			bundles,
			signatures,
			address(0),
			_reservePrice
		);

		hoax(bidder);
		auction.createBid{ value: _bidAmount }(tokenId, 0);

		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		uint256 treasuryFee = (_bidAmount * 200) / 10000;
		uint256 redistributionFee = (_bidAmount * 500) / 10000;
		uint256 sellerProceeds = _bidAmount - treasuryFee - redistributionFee;

		assertEq(
			IERC20(address(mockWeth)).balanceOf(treasuryRecipient),
			treasuryFee
		);
		assertEq(
			IERC20(address(mockWeth)).balanceOf(redistributionRecipient),
			redistributionFee
		);
		assertEq(artistPayout.balance, sellerProceeds);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(trackMinter), 1);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(bundles[0].tokenId),
			trackMinter
		);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(bundles[1].tokenId),
			bidder
		);
	}

	function testFuzz_SettleReserveAuctionSendsERC20FundsToSplits(
		uint256 _reservePrice,
		uint256 _bidAmount
	) public {
		vm.assume(_reservePrice > 0);
		vm.assume(_bidAmount >= _reservePrice);
		vm.assume(_bidAmount < type(uint256).max / 5000);
		ERC20ReturnTrueMock mockERC20 = new ERC20ReturnTrueMock();
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(
			bundles,
			signatures,
			address(mockERC20),
			_reservePrice
		);

		hoax(bidder);
		auction.createBid(tokenId, _bidAmount);
		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		uint256 treasuryFee = (_bidAmount * 200) / 10000;
		uint256 redistributionFee = (_bidAmount * 500) / 10000;
		uint256 sellerProceeds = _bidAmount - treasuryFee - redistributionFee;

		assertEq(
			IERC20(address(mockERC20)).balanceOf(treasuryRecipient),
			treasuryFee
		);
		assertEq(
			IERC20(address(mockERC20)).balanceOf(redistributionRecipient),
			redistributionFee
		);
		assertEq(
			IERC20(address(mockERC20)).balanceOf(artistPayout),
			sellerProceeds
		);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(trackMinter), 1);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(bundles[0].tokenId),
			trackMinter
		);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(bundles[1].tokenId),
			bidder
		);
	}

	function testFuzz_SendEthProceedsToArtistAddress(
		uint256 _reservePrice,
		uint256 _bidAmount
	) public {
		vm.deal(bidder, _bidAmount);
		vm.assume(_bidAmount < 2_000_000_000_000 ether);
		vm.assume(_reservePrice > 0);
		vm.assume(_bidAmount >= _reservePrice);
		vm.assume(_bidAmount < type(uint256).max / 5000);

		MetadataBundle[2] memory bundles = _createBundles();
		bundles[0].payout = payable(address(0));
		Signature[2] memory sigs = _getBundleSignatures(bundles);

		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, sigs, address(0), _reservePrice);

		hoax(bidder);
		auction.createBid{ value: _bidAmount }(tokenId, 0);

		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		uint256 treasuryFee = (_bidAmount * 200) / 10000;
		uint256 redistributionFee = (_bidAmount * 500) / 10000;
		uint256 sellerProceeds = _bidAmount - treasuryFee - redistributionFee;

		assertEq(
			IERC20(address(mockWeth)).balanceOf(treasuryRecipient),
			treasuryFee
		);
		assertEq(
			IERC20(address(mockWeth)).balanceOf(redistributionRecipient),
			redistributionFee
		);
		assertEq(trackMinter.balance, sellerProceeds);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(trackMinter), 1);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(bundles[0].tokenId),
			trackMinter
		);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(bundles[1].tokenId),
			bidder
		);
	}

	function testFuzz_SettleReserveAuctionSendsERC20FundsToArtistAddress(
		uint256 _reservePrice,
		uint256 _bidAmount
	) public {
		vm.assume(_reservePrice > 0);
		vm.assume(_bidAmount >= _reservePrice);
		vm.assume(_bidAmount < type(uint256).max / 5000);

		ERC20ReturnTrueMock mockERC20 = new ERC20ReturnTrueMock();

		MetadataBundle[2] memory bundles = _createBundles();
		bundles[0].payout = payable(address(0));
		Signature[2] memory sigs = _getBundleSignatures(bundles);

		vm.prank(trackMinter);
		auction.createReserveAuction(
			bundles,
			sigs,
			address(mockERC20),
			_reservePrice
		);

		hoax(bidder);
		auction.createBid(tokenId, _bidAmount);
		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		uint256 treasuryFee = (_bidAmount * 200) / 10000;
		uint256 redistributionFee = (_bidAmount * 500) / 10000;
		uint256 sellerProceeds = _bidAmount - treasuryFee - redistributionFee;

		assertEq(
			IERC20(address(mockERC20)).balanceOf(treasuryRecipient),
			treasuryFee
		);
		assertEq(
			IERC20(address(mockERC20)).balanceOf(redistributionRecipient),
			redistributionFee
		);
		assertEq(IERC20(address(mockERC20)).balanceOf(trackMinter), sellerProceeds);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(trackMinter), 1);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(bundles[0].tokenId),
			trackMinter
		);
		assertEq(
			ERC721(address(auction.rewardToken())).ownerOf(bundles[1].tokenId),
			bidder
		);
	}

	function test_ContractBidderAcceptsEthRefunds() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), .1 ether);

		// Contract is original bidder
		hoax(address(contractBidder));
		uint256 originalBalance = address(contractBidder).balance;
		contractBidder.createETHBid(tokenId, .1 ether);

		// Bidder outbids contract
		hoax(bidder);
		auction.createBid{ value: .3 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		// Contract bidder should have 0.1 eth refunded
		assertEq(address(contractBidder).balance, originalBalance);
	}

	function test_ContractBidderRejectsEthRefunds() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), .1 ether);

		// Contract is original bidder
		hoax(address(contractBidder));
		contractBidder.createETHBid(tokenId, .1 ether);
		contractBidder.disableReceiving();

		// Bidder outbids contract
		hoax(bidder);
		auction.createBid{ value: .3 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		// Contract bidder should have 0.1 weth refunded
		assertEq(
			IERC20(address(mockWeth)).balanceOf(address(contractBidder)),
			.1 ether
		);
	}

	function test_CancelAuctionThatsEndedReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), .1 ether);

		// Bidder bids
		hoax(bidder);
		auction.createBid{ value: .3 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_AuctionEnded.selector
		);
		vm.prank(trackMinter);
		auction.cancelReserveAuction(tokenId);
	}

	function _makeDomainHash() private view returns (bytes32) {
		bytes32 _EIP712DOMAIN_TYPEHASH = keccak256(
			"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
		);
		return
			keccak256(
				abi.encode(
					_EIP712DOMAIN_TYPEHASH,
					keccak256("SonaReserveAuction"), // name
					keccak256("1"), // version
					block.chainid, // chain ID
					address(auction) // verifying contract
				)
			);
	}

	function _hashFromMemory(
		MetadataBundle memory bundle
	) internal pure returns (bytes32) {
		bytes32 _METADATABUNDLE_TYPEHASH = keccak256(
			"MetadataBundle(uint256 tokenId,address payout,address rewardsPayout,string arweaveTxId)"
		);
		return
			keccak256(
				abi.encode(
					_METADATABUNDLE_TYPEHASH,
					bundle.tokenId,
					bundle.payout,
					bundle.rewardsPayout,
					keccak256(bytes(bundle.arweaveTxId))
				)
			);
	}

	function _getBundleHash(
		MetadataBundle memory _bundle
	) private view returns (bytes32) {
		bytes32 domainSeparator = _makeDomainHash();
		return
			keccak256(
				abi.encodePacked("\x19\x01", domainSeparator, _hashFromMemory(_bundle))
			);
	}
}
