// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { SonaReserveAuction } from "../SonaReserveAuction.sol";
import { SonaRewardToken } from "../SonaRewardToken.sol";
import { ISonaReserveAuction } from "../interfaces/ISonaReserveAuction.sol";
import { IERC721AUpgradeable } from "erc721a-upgradeable/interfaces/IERC721AUpgradeable.sol";
import { Util } from "./Util.sol";
import "forge-std/console.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { MockWeth9, IWETH } from "./mock/MockWeth9.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { ERC20ReturnTrueMock, ERC20NoReturnMock, ERC20ReturnFalseMock } from "./mock/ERC20Mock.sol";
import { MockWeth9, IWETH } from "./mock/MockWeth9.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

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
	address public authorizer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

	uint256 public tokenId = (uint256(uint160(trackMinter)) << 96) | 69;

	// Weth
	MockWeth9 public mockWeth = new MockWeth9();

	function setUp() public {
		vm.startPrank(rootOwner);
		// WARNING: deployment order matters for the signatures below
		SonaRewardToken rewardTokenBase = new SonaRewardToken();
		SonaReserveAuction auctionBase = new SonaReserveAuction();
		ERC1967Proxy proxy = new ERC1967Proxy(
			address(auctionBase),
			abi.encodeWithSelector(SonaReserveAuction.initialize.selector, treasuryRecipient, redistributionRecipient, authorizer, rewardTokenBase, address(0), mockWeth)
		);
		auction = SonaReserveAuction(address(proxy));
		vm.stopPrank();
	}

	function test_revertsWithInvalidAddress() public {
		SonaRewardToken rewardTokenBase = new SonaRewardToken();
		SonaReserveAuction auctionBase = new SonaReserveAuction();
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_InvalidAddress.selector);
		new ERC1967Proxy(address(auctionBase), abi.encodeWithSelector(SonaReserveAuction.initialize.selector, address(0), redistributionRecipient, authorizer, rewardTokenBase, address(0), mockWeth));

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_InvalidAddress.selector);
		new ERC1967Proxy(address(auctionBase), abi.encodeWithSelector(SonaReserveAuction.initialize.selector, treasuryRecipient, address(0), authorizer, rewardTokenBase, address(0), mockWeth));

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_InvalidAddress.selector);
		new ERC1967Proxy(
			address(auctionBase),
			abi.encodeWithSelector(SonaReserveAuction.initialize.selector, treasuryRecipient, redistributionRecipient, address(0), rewardTokenBase, address(0), mockWeth)
		);

		vm.expectRevert("ERC1967: new implementation is not a contract");
		new ERC1967Proxy(address(auctionBase), abi.encodeWithSelector(SonaReserveAuction.initialize.selector, treasuryRecipient, redistributionRecipient, authorizer, address(0), address(0), mockWeth));
	}

	function _createSignedBundles() private pure returns (MetadataBundle[2] memory bundles, Signature[2] memory signatures) {
		MetadataBundle memory artistBundle = MetadataBundle("Hello World!", 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000044);
		MetadataBundle memory collectorBundle = MetadataBundle("Hello World", 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000045);
		Signature memory artistSignature = Signature(28, 0x17a63f8e164ff300abc7e6f46fcecbd6f86ceb999446c6c9f3d7f2fda15603cf, 0x7effc1119b1cb2b1f8974979da63ac29089e2f484718789462263de38a6e7cd4);
		Signature memory collectorSignature = Signature(27, 0x0d43e4410a8d0c45dc98354210e58c9af0c00baa738a41ffac5daef8d6388e95, 0x2d409dd510323b6066ef2fbf8a766734884295c907c6c6fbb7b1871b61ff1120);

		bundles = [artistBundle, collectorBundle];
		signatures = [artistSignature, collectorSignature];
	}

	function test_CreateReserveAuction() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
		vm.stopPrank();

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

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
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_AlreadyListed.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
		vm.stopPrank();
	}

	function test_CreateReserveAuctionZeroReserveReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_ReservePriceCannotBeZero.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 0);
		vm.stopPrank();
	}

	function test_CreateReserveAuctionWithInvalidArtistBundleReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		signatures[0].v = 69;

		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_BundlesNotAuthorized.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateReserveAuctionWithInvalidCollectorBundleReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		signatures[1].v = 69;

		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_BundlesNotAuthorized.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	// TODO generate valid signature
	function xtest_CreateReserveAuctionWithInvalidArtistTokenIdReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		bundles[0].tokenId = (uint256(uint160(trackMinter)) << 96) | 69;

		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_InvalidTokenIds.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	// TODO generate valid signature
	function xtest_CreateReserveAuctionWithInvalidCollectorTokenIdReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		bundles[1].tokenId = (uint256(uint160(trackMinter)) << 96) | 70;

		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_InvalidTokenIds.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateReserveAuctionWithInvalidCallerReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.startPrank(address(0xcccccc));

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateBid() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

		assertEq(auctionData.currentBidAmount, 1.1 ether);
		assertEq(auctionData.currentBidder, bidder);
	}

	function test_CreateBidWithInvalidAuctionReverts() public {
		hoax(bidder);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_InvalidAuction.selector);
		auction.createBid{ value: 1.1 ether }(88, 0);
	}

	function test_CreateBidWithZeroBidReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_BidTooLow.selector);
		auction.createBid{ value: 0.0 ether }(tokenId, 0);
	}

	function test_CreateBidWithLowBidReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_BidTooLow.selector);
		auction.createBid{ value: 0.9 ether }(tokenId, 0);
	}

	function test_CreateBidWithSameBidder() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);
		auction.createBid{ value: 1.2 ether }(tokenId, 0);
	}

	function test_CreateLowBidWithSameBidderReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);
		vm.expectRevert(SonaReserveAuction_BidTooLow.selector);
		auction.createBid{ value: 1.0 ether }(tokenId, 0);
	}

	function test_CreateMultipleBidsReturnsOriginalERC20BidderFunds() public {
		ERC20ReturnTrueMock mockERC20 = new ERC20ReturnTrueMock();
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(mockERC20), 10);

		deal(address(mockERC20), bidder, 100);
		vm.prank(bidder);
		auction.createBid(tokenId, 100);

		hoax(secondBidder);
		auction.createBid(tokenId, 110);

		assertEq(IERC20(address(mockERC20)).balanceOf(bidder), 100);
	}

	function test_CreateMultipleBidsReturnsOriginalETHBidderFunds() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder, 1.1 ether);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		hoax(secondBidder);
		auction.createBid{ value: 2 ether }(tokenId, 0);

		assertEq(bidder.balance, 1.1 ether);
	}

	function test_CreateBidWithOnExpiredAuctionReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		auction.createBid{ value: 1.1 ether }(tokenId, 0);
		vm.warp(2 days);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_AuctionEnded.selector);
		auction.createBid{ value: 1.2 ether }(tokenId, 0);
	}

	function test_CancelAuction() public {
		vm.startPrank(trackMinter);

		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
		auction.cancelReserveAuction(tokenId);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(0);

		assertEq(auctionData.trackSeller, address(0));
		assertEq(auctionData.reservePrice, 0);
	}

	function test_UpdateReserveAuctionPriceWithZeroReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_ReservePriceCannotBeZero.selector);
		auction.updateReserveAuctionPrice(tokenId, 0);
	}

	function test_UpdateReserveAuctionPrice() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		auction.updateReserveAuctionPrice(tokenId, 2 ether);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

		assertEq(auctionData.reservePrice, 2 ether);
	}

	function test_UpdateReserveAuctionPriceAuctionAlreadyLive() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.startPrank(trackMinter);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_AuctionIsLive.selector);
		auction.updateReserveAuctionPrice(tokenId, 2 ether);
	}

	function test_UpdateReserveAuctionPriceWithInvalidCallerReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.startPrank(makeAddr("unauthorizedUser"));

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector);
		auction.updateReserveAuctionPrice(tokenId, 2 ether);
	}

	function test_CreateDuplicateFailsAfterSettlement() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
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
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

		assertEq(auctionData.trackSeller, address(0));
		assertEq(auctionData.reservePrice, 0);
		assertEq(IERC721AUpgradeable(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(IERC721AUpgradeable(address(auction.rewardToken())).balanceOf(trackMinter), 1);
	}

	function test_SettleReserveAuctionWhileLiveReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.prank(trackMinter);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_AuctionIsLive.selector);
		auction.settleReserveAuction(tokenId);
	}

	function test_SettleReserveAuctionInvalidCallerReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector);
		auction.settleReserveAuction(tokenId);
	}

	function test_CancelInvalidReserveAuctionReverts() public {
		vm.startPrank(trackMinter);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_InvalidAuction.selector);
		auction.cancelReserveAuction(tokenId);
	}

	function test_CancelReserveAuctionInvalidCallerReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.startPrank(makeAddr("unauthorizedUser"));

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector);
		auction.cancelReserveAuction(0);
	}

	function test_CancelReserveAuctionStillLiveReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_AuctionIsLive.selector);
		auction.cancelReserveAuction(tokenId);
	}

	function test_CreateReserveAuctionWithERC20Currency() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.startPrank(trackMinter);
		auction.createReserveAuction(bundles, signatures, nonEthToken, 10000);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

		assertEq(auctionData.reservePrice, 10000);
		assertEq(auctionData.trackSeller, trackMinter);
		assertEq(auctionData.currency, nonEthToken);

		vm.stopPrank();
	}

	function test_CreateBidERC20() public {
		ERC20ReturnTrueMock mockRewardToken = new ERC20ReturnTrueMock();
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(mockRewardToken), 10000);

		hoax(bidder);
		auction.createBid(tokenId, 10000);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

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
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(brokenMockRewardToken), 10000);

		hoax(bidder);
		vm.expectRevert(bytes(""));
		auction.createBid(tokenId, 10000);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

		assertEq(auctionData.currentBidAmount, 0);
		assertEq(auctionData.currentBidder, address(0));
	}

	function test_CreateBidWithInvalidERC20PermissionsReverts() public {
		ERC20ReturnFalseMock mockRewardToken = new ERC20ReturnFalseMock();
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(mockRewardToken), 10000);

		hoax(bidder);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_TransferFailed.selector);
		auction.createBid(tokenId, 10000);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

		assertEq(auctionData.currentBidAmount, 0);
		assertEq(auctionData.currentBidder, address(0));
	}

	function test_CreateBidERC20WithEthReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, nonEthToken, 10000);

		hoax(bidder);
		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_InvalidCurrency.selector);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

		assertEq(auctionData.currentBidAmount, 0);
		assertEq(auctionData.currentBidder, address(0));
	}

	function test_UpdateReserveAuctionPriceAndCurrency() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(tokenId);

		assertEq(auctionData.reservePrice, 1 ether);
		assertEq(auctionData.trackSeller, trackMinter);
		assertEq(auctionData.currency, address(0));

		vm.prank(trackMinter);
		auction.updateReserveAuctionPriceAndCurrency(nonEthToken, tokenId, 100000);

		ISonaReserveAuction.Auction memory newAuctionData = auction.getAuction(tokenId);

		assertEq(newAuctionData.reservePrice, 100000);
		assertEq(newAuctionData.trackSeller, trackMinter);
		assertEq(newAuctionData.currency, nonEthToken);
	}

	function test_UpdateReserveAuctionPriceAndCurrencyAuctionZeroPriceReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.startPrank(trackMinter);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_ReservePriceCannotBeZero.selector);
		auction.updateReserveAuctionPriceAndCurrency(nonEthToken, tokenId, 0);
	}

	function test_UpdateReserveAuctionPriceAndCurrencyAuctionAlreadyLive() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.startPrank(trackMinter);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_AuctionIsLive.selector);
		auction.updateReserveAuctionPriceAndCurrency(nonEthToken, tokenId, 100000);
	}

	function test_UpdateReserveAuctionPriceAndCurrencyWithInvalidCallerReverts() public {
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.startPrank(makeAddr("unauthorizedUser"));

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector);
		auction.updateReserveAuctionPriceAndCurrency(nonEthToken, tokenId, 100000);
	}

	function testFuzz_SettleReserveAuctionSendsWethFundsToRecipients(uint256 _reservePrice, uint256 _bidAmount) public {
		vm.deal(bidder, _bidAmount);
		vm.assume(_bidAmount < 2_000_000_000_000 ether);
		vm.assume(_reservePrice > 0);
		vm.assume(_bidAmount >= _reservePrice);
		vm.assume(_bidAmount < type(uint256).max / 5000);
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), _reservePrice);

		hoax(bidder);
		auction.createBid{ value: _bidAmount }(tokenId, 0);

		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		uint256 treasuryFee = (_bidAmount * 200) / 10000;
		uint256 redistributionFee = (_bidAmount * 500) / 10000;
		uint256 sellerProceeds = _bidAmount - treasuryFee - redistributionFee;

		assertEq(IERC20(address(mockWeth)).balanceOf(treasuryRecipient), treasuryFee);
		assertEq(IERC20(address(mockWeth)).balanceOf(redistributionRecipient), redistributionFee);
		assertEq(trackMinter.balance, sellerProceeds);
	}

	function testFuzz_SettleReserveAuctionSendsERC20FundsToRecipients(uint256 _reservePrice, uint256 _bidAmount) public {
		vm.assume(_reservePrice > 0);
		vm.assume(_bidAmount >= _reservePrice);
		vm.assume(_bidAmount < type(uint256).max / 5000);
		ERC20ReturnTrueMock mockERC20 = new ERC20ReturnTrueMock();
		(MetadataBundle[2] memory bundles, Signature[2] memory signatures) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(mockERC20), _reservePrice);

		hoax(bidder);
		auction.createBid(tokenId, _bidAmount);
		vm.warp(2 days);

		vm.prank(trackMinter);
		auction.settleReserveAuction(tokenId);

		uint256 treasuryFee = (_bidAmount * 200) / 10000;
		uint256 redistributionFee = (_bidAmount * 500) / 10000;
		uint256 sellerProceeds = _bidAmount - treasuryFee - redistributionFee;

		assertEq(IERC20(address(mockERC20)).balanceOf(treasuryRecipient), treasuryFee);
		assertEq(IERC20(address(mockERC20)).balanceOf(redistributionRecipient), redistributionFee);
		assertEq(IERC20(address(mockERC20)).balanceOf(trackMinter), sellerProceeds);
	}
}
