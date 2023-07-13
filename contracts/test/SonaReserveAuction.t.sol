// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { SonaReserveAuction } from "../SonaReserveAuction.sol";
import { SonaRewardToken } from "../SonaRewardToken.sol";
import { ISonaReserveAuction } from "../interfaces/ISonaReserveAuction.sol";
import { ISonaAuthorizer } from "../interfaces/ISonaAuthorizer.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { Util } from "./Util.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { Weth9Mock, IWETH } from "./mock/Weth9Mock.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { ERC20ReturnTrueMock, ERC20NoReturnMock, ERC20ReturnFalseMock } from "./mock/ERC20Mock.sol";
import { ContractBidderMock } from "./mock/ContractBidderMock.sol";
import { Weth9Mock, IWETH } from "./mock/Weth9Mock.sol";

/* solhint-disable max-states-count */
contract SonaReserveAuctionTest is Util, SonaReserveAuction {
	SonaReserveAuction public auction;
	address public trackAddress;

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
	string public mnemonic =
		"test test test test test test test test test test test junk";
	uint256 public authorizerKey = vm.deriveKey(mnemonic, 0);
	address public authorizer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
	address payable public artistPayout = payable(address(25));

	uint256 public tokenId = (uint256(uint160(trackMinter)) << 96) | 69;

	// Weth
	Weth9Mock public mockWeth = new Weth9Mock();

	// Contract bidder
	ContractBidderMock public contractBidder;

	function setUp() public {
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
			28,
			0xffc0fb30061f17a53c5c2467f59a3eb97e8ec4b5b0c06fa52142daf608d12d8b,
			0x66f4b7b6d74b4c84f92f2bae1661bb6000a0d8b5806bb1862368e39b35bb8183
		);
		Signature memory collectorSignature = Signature(
			27,
			0x54826a459211de0cc74e8ee384b1c7d051b8ba6eb89d2e8b337ce6e8e3d0fe26,
			0x5217cb99f9f960c6bfb2ada761d0a7da7473468e4a4ff75c0effac2897d21cf2
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
			payout: artistPayout
		});
		MetadataBundle memory collectorBundle = MetadataBundle({
			arweaveTxId: "Hello World",
			tokenId: 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000045,
			payout: payable(address(0))
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
		vm.expectRevert(
			ISonaAuthorizer.SonaAuthorizer_InvalidSignature.selector
		);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateReserveAuctionWithInvalidCollectorBundleReverts() public {
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		signatures[1].v = 69;

		vm.startPrank(trackMinter);
		vm.expectRevert(
			ISonaAuthorizer.SonaAuthorizer_InvalidSignature.selector
		);
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
		(
			MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
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

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

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
			"MetadataBundle(uint256 tokenId,address payout,string arweaveTxId)"
		);
		return
			keccak256(
				abi.encode(
					_METADATABUNDLE_TYPEHASH,
					bundle.tokenId,
					bundle.payout,
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
