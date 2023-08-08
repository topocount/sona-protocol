// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { SonaReserveAuction } from "../SonaReserveAuction.sol";
import { SonaRewardToken, ISonaRewardToken } from "../SonaRewardToken.sol";
import { ISonaReserveAuction } from "../interfaces/ISonaReserveAuction.sol";
import { ISonaAuthorizer } from "../interfaces/ISonaAuthorizer.sol";
import { AuctionSigner } from "./utils/AuctionSigner.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { Util } from "./Util.sol";
import { SplitHelpers } from "./util/SplitHelpers.t.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { Weth9Mock, IWETH } from "./mock/Weth9Mock.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { MockERC20 } from "../../lib/solady/test/utils/mocks/MockERC20.sol";
import { ERC20ReturnTrueMock, ERC20NoReturnMock, ERC20ReturnFalseMock } from "./mock/ERC20Mock.sol";
import { ContractBidderMock } from "./mock/ContractBidderMock.sol";
import { ISplitMain, SplitMain } from "../payout/SplitMain.sol";
import { ISonaSwap } from "lib/common/ISonaSwap.sol";

/* solhint-disable max-states-count */
contract SonaReserveAuctionTest is SplitHelpers {
	event RewardTokenMetadataUpdated(
		uint256 indexed tokenId,
		string txId,
		address payout
	);

	address public swapAddr;
	SonaReserveAuction public auctionBase;
	SonaRewardToken public rewardTokenBase;

	uint256 public mainnetFork;
	string public MAINNET_RPC_URL = vm.envString("MAINNET_FORK_RPC_URL");

	address public constant dataFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
	IWETH public constant WETH9 =
		IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
	address public constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
	address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

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
	address payable public artistPayout = payable(address(25));
	address payable public zeroPayout = payable(address(0));

	uint256 public tokenId = (uint256(uint160(trackMinter)) << 96) | 69;

	// Weth
	Weth9Mock public mockWeth = new Weth9Mock();
	// mockUSDC
	MockERC20 public mockUSDC = new MockERC20("Mock Token", "USDC", 6);

	// Contract bidder
	ContractBidderMock public contractBidder;

	function setUp() public {
		swapAddr = deployCode(
			"SonaSwap.sol",
			abi.encode(address(0), address(0), mockUSDC, mockWeth)
		);
		splitMainImpl = new SplitMain(
			mockWeth,
			IERC20(address(mockUSDC)),
			ISonaSwap(swapAddr)
		);
		vm.startPrank(rootOwner);
		// WARNING: deployment order matters for the signatures below
		rewardTokenBase = new SonaRewardToken();
		auctionBase = new SonaReserveAuction();
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
		rewardTokenBase = new SonaRewardToken();
		auctionBase = new SonaReserveAuction();
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
		returns (ISonaRewardToken.MetadataBundle[2] memory bundles, Signature[2] memory signatures)
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
		returns (ISonaRewardToken.MetadataBundle[2] memory bundles)
	{
		ISonaRewardToken.MetadataBundle memory artistBundle = ISonaRewardToken.MetadataBundle({
			arweaveTxId: "Hello World!",
			tokenId: 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000044,
			payout: artistPayout
		});
		ISonaRewardToken.MetadataBundle memory collectorBundle = ISonaRewardToken.MetadataBundle({
			arweaveTxId: "Hello World",
			tokenId: 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000045,
			payout: payable(address(0))
		});

		bundles = [artistBundle, collectorBundle];
	}

	function test_CreateReserveAuction() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
		assertEq(auctionData.tokenMetadata.arweaveTxId, bundles[1].arweaveTxId);
		assertEq(auctionData.tokenMetadata.tokenId, bundles[1].tokenId);
	}

	function test_CreateReserveAuctionMultipleReverts() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		signatures[0].v = 69;

		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaAuthorizer.SonaAuthorizer_InvalidSignature.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateReserveAuctionWithInvalidCollectorBundleReverts() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		signatures[1].v = 69;

		vm.startPrank(trackMinter);
		vm.expectRevert(ISonaAuthorizer.SonaAuthorizer_InvalidSignature.selector);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateReserveAuctionWithInvalidArtistTokenIdReverts() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.startPrank(address(0xcccccc));

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_NotAuthorized.selector
		);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);
	}

	function test_CreateBid() public {
		ISonaRewardToken.MetadataBundle[2] memory bundles = _createBundles();
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_BidTooLow.selector);
		auction.createBid{ value: 0.0 ether }(tokenId, 0);
	}

	function test_CreateBidWithLowBidReverts() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		vm.expectRevert(ISonaReserveAuction.SonaReserveAuction_BidTooLow.selector);
		auction.createBid{ value: 0.9 ether }(tokenId, 0);
	}

	function test_CreateBidWithSameBidder() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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

	function test_SettleReserveAuctionWithNoRewardsPayoutSet() public {
		ISonaRewardToken.MetadataBundle[2] memory bundles = _createBundles();
		bundles[0].payout = payable(address(0));
		Signature[2] memory signatures = _getBundleSignatures(bundles);
		vm.expectEmit(true, false, false, true, address(auction.rewardToken()));
		emit RewardTokenMetadataUpdated(
			tokenId - 1,
			bundles[0].arweaveTxId,
			bundles[0].payout
		);
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.warp(2 days);

		vm.expectEmit(true, false, false, true, address(auction.rewardToken()));
		emit RewardTokenMetadataUpdated(
			tokenId,
			bundles[1].arweaveTxId,
			payable(address(0))
		);
		vm.expectEmit(true, false, false, false, address(auction));
		emit ReserveAuctionSettled(tokenId);
		vm.prank(trackMinter);
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

	function test_SettleReserveAuction() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
		assertEq(metadata.payout, artistPayout);
		metadata = token.getRewardTokenMetadata(tokenId);
		assertEq(metadata.payout, address(0));
	}

	function test_DistributeERC20ToSplit() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		ISonaRewardToken.MetadataBundle[2] memory bundles = _createBundles();
		bundles[1].payout = split;
		Signature[2] memory signatures = _getBundleSignatures(bundles);
		vm.prank(trackMinter);
		auction.createReserveAuction(
			bundles,
			signatures,
			address(mockUSDC),
			1 ether
		);

		uint256 bidAmount = 1.1 ether;
		mockUSDC.mint(bidder, bidAmount);
		hoax(bidder);
		mockUSDC.approve(address(auction), bidAmount);

		hoax(bidder);
		auction.createBid(tokenId, bidAmount);

		vm.warp(2 days);

		uint initialBalance0 = mockUSDC.balanceOf(accounts[0]);
		uint initialBalance1 = mockUSDC.balanceOf(accounts[1]);

		vm.prank(trackMinter);
		auction.settleReserveAuctionAndDistributePayout(tokenId, accounts, amounts);

		uint finalBalance0 = mockUSDC.balanceOf(accounts[0]);
		uint finalBalance1 = mockUSDC.balanceOf(accounts[1]);

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
		uint256 twoDays = 15_000;
		uint256 forkBlock = 17828120 - twoDays;
		mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, forkBlock);
		swapAddr = deployCode(
			"SonaSwap.sol",
			abi.encode(dataFeed, router, USDC, WETH9)
		);
		splitMainImpl = new SplitMain(WETH9, IERC20(USDC), ISonaSwap(swapAddr));
		rewardTokenBase = new SonaRewardToken();
		auctionBase = new SonaReserveAuction();
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
				WETH9
			)
		);
		auction = SonaReserveAuction(address(proxy));
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		ISonaRewardToken.MetadataBundle[2] memory bundles = _createBundles();
		bundles[1].payout = split;
		Signature[2] memory signatures = _getBundleSignatures(bundles);

		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		vm.rollFork(forkBlock + twoDays);

		uint initialBalance0 = IERC20(USDC).balanceOf(accounts[0]);
		uint initialBalance1 = IERC20(USDC).balanceOf(accounts[1]);

		vm.prank(trackMinter);
		auction.settleReserveAuctionAndDistributePayout(tokenId, accounts, amounts);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		uint256 quote = ISonaSwap(swapAddr).getQuote(1.1 ether);
		uint256 expectedBalance = ((quote * 93) / 100 / 2);
		uint finalBalance0 = IERC20(USDC).balanceOf(accounts[0]);
		uint finalBalance1 = IERC20(USDC).balanceOf(accounts[1]);

		assertApproxEqRelDecimal(
			finalBalance0 - initialBalance0,
			expectedBalance,
			5e15,
			6
		); // 0.5% = 5e15
		assertApproxEqRelDecimal(
			finalBalance1 - initialBalance1,
			expectedBalance,
			5e15,
			6
		); // 0.5% = 5e15

		assertEq(auctionData.trackSeller, address(0));
		assertEq(auctionData.reservePrice, 0);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(bidder), 1);
		assertEq(ERC721(address(auction.rewardToken())).balanceOf(trackMinter), 1);
	}

	function test_SettleReserveAuctionWhileLiveReverts() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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

	function test_CancelInvalidReserveAuctionReverts() public {
		vm.startPrank(trackMinter);

		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidAuction.selector
		);
		auction.cancelReserveAuction(tokenId);
	}

	function test_CancelReserveAuctionInvalidCallerReverts() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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

	function test_CreateBidEthWithERC20Reverts() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 0.05 ether);

		hoax(bidder);
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidCurrency.selector
		);
		auction.createBid(tokenId, 0.05 ether);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.currentBidAmount, 0);
		assertEq(auctionData.currentBidder, address(0));
	}

	function test_UpdateReserveAuctionPayoutAddress() public {
		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.tokenMetadata.payout, address(0));

		address payable newPayout = payable(address(26));

		vm.prank(trackMinter);
		auction.updateArtistPayoutAddress(tokenId, newPayout);

		ISonaReserveAuction.Auction memory newAuctionData = auction.getAuction(
			tokenId
		);

		assertEq(newAuctionData.tokenMetadata.payout, newPayout);

		hoax(bidder);
		auction.createBid{ value: 1.1 ether }(tokenId, 0);

		newPayout = payable(address(27));

		vm.prank(trackMinter);
		vm.expectEmit(true, false, false, true, address(auction));
		emit PayoutAddressUpdated(tokenId, newPayout);
		auction.updateArtistPayoutAddress(tokenId, newPayout);

		newAuctionData = auction.getAuction(tokenId);

		assertEq(newAuctionData.tokenMetadata.payout, newPayout);
	}

	function test_InvalidUpdateReserveAuctionPayoutAddress() public {
		address payable newPayout = payable(address(26));
		// cannot be updated before auction is created
		vm.expectRevert(
			ISonaReserveAuction.SonaReserveAuction_InvalidAuction.selector
		);
		vm.prank(trackMinter);
		auction.updateArtistPayoutAddress(tokenId, newPayout);

		(
			ISonaRewardToken.MetadataBundle[2] memory bundles,
			Signature[2] memory signatures
		) = _createSignedBundles();
		vm.prank(trackMinter);
		auction.createReserveAuction(bundles, signatures, address(0), 1 ether);

		ISonaReserveAuction.Auction memory auctionData = auction.getAuction(
			tokenId
		);

		assertEq(auctionData.tokenMetadata.payout, address(0));

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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
		ISonaRewardToken.MetadataBundle[2] memory bundles = _createBundles();
		bundles[1].payout = artistPayout;
		Signature[2] memory signatures = _getBundleSignatures(bundles);
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
		ISonaRewardToken.MetadataBundle[2] memory bundles = _createBundles();
		bundles[1].payout = artistPayout;
		Signature[2] memory signatures = _getBundleSignatures(bundles);
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

		ISonaRewardToken.MetadataBundle[2] memory bundles = _createBundles();
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

		ISonaRewardToken.MetadataBundle[2] memory bundles = _createBundles();
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
			ISonaRewardToken.MetadataBundle[2] memory bundles,
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
}
