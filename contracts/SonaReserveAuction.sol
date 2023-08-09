// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

//  ___  _____  _  _    __      ___  ____  ____  ____    __    __  __
// / __)(  _  )( \( )  /__\    / __)(_  _)(  _ \( ___)  /__\  (  \/  )
// \__ \ )(_)(  )  (  /(__)\   \__ \  )(   )   / )__)  /(__)\  )    (
// (___/(_____)(_)\_)(__)(__)  (___/ (__) (_)\_)(____)(__)(__)(_/\/\_)

import { ISonaReserveAuction } from "./interfaces/ISonaReserveAuction.sol";
import { SonaTokenAuthorizer } from "./SonaTokenAuthorizer.sol";
import { ISplitMain } from "./payout/interfaces/ISplitMain.sol";
import { Initializable } from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import { SonaAdmin } from "./access/SonaAdmin.sol";
import { IERC721Upgradeable as IERC721 } from "openzeppelin-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ISonaRewardToken } from "./interfaces/ISonaRewardToken.sol";
import { AddressableTokenId } from "./utils/AddressableTokenId.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { ZeroCheck } from "./utils/ZeroCheck.sol";

contract SonaReserveAuction is
	ISonaReserveAuction,
	Initializable,
	SonaAdmin,
	SonaTokenAuthorizer
{
	using AddressableTokenId for uint256;
	using ZeroCheck for address;
	using ZeroCheck for address payable;

	/*//////////////////////////////////////////////////////////////
	/                         CONSTANTS
	//////////////////////////////////////////////////////////////*/

	// @dev The minimum duration of an auction. (24 hours)
	uint256 private constant _AUCTION_DURATION = 24 hours;
	// @dev The duration you may extend an auction by if you meet the price threshold. (15 minutes)
	uint256 private constant _AUCTION_EXTENSION_DURATION = 15 minutes;
	// @dev The minimum price threshold you must meet to extend an auction. (5%)
	uint256 private constant _AUCTION_EXTENSION_BPS = 500;
	// @dev The redistribution fee charged to the seller (5%)
	uint256 private constant _AUCTION_REDISTRIBUTION_FEE_BPS = 500;
	// @dev The treasury fee charged to the seller (2%)
	uint256 private constant _AUCTION_TREASURY_FEE_BPS = 200;

	/*//////////////////////////////////////////////////////////////
	/                         STATE
	//////////////////////////////////////////////////////////////*/

	// @dev The recipient of the treasury fee
	address private _treasuryFeeRecipient;
	// @dev The recipient of the redistribution fee
	address private _redistributionFeeRecipient;
	// @dev The instance of the rewardToken contract
	ISonaRewardToken public rewardToken;
	/// @dev splits contract to execute distributions on
	ISplitMain public splitMain;
	// @dev Weth
	IWETH private _weth;

	/*//////////////////////////////////////////////////////////////
	/                          MAPPINGS
	//////////////////////////////////////////////////////////////*/

	mapping(uint256 => Auction) public auctions;
	mapping(bytes32 => bool) private _uriExists;

	/*//////////////////////////////////////////////////////////////
	/                         MODIFIERS
	//////////////////////////////////////////////////////////////*/

	/// @dev Modifier that ensures the calling wallet has the admin role or is the specified owner
	modifier onlySonaAdminOrApprovedTokenOperator(uint256 _tokenId) {
		if (_tokenId.getAddress() != msg.sender && !isSonaAdmin(msg.sender))
			revert SonaReserveAuction_NotAuthorized();
		_;
	}

	modifier bundlesAuthorized(
		ISonaRewardToken.TokenMetadatas calldata bundles,
		Signature calldata signature
	) {
		if (!_verify(bundles, signature.v, signature.r, signature.s))
			revert SonaAuthorizer_InvalidSignature();
		_;
	}

	/*//////////////////////////////////////////////////////////////
								Constructor
	//////////////////////////////////////////////////////////////*/
	constructor() {
		_disableInitializers();
	}

	/*//////////////////////////////////////////////////////////////
	/                     PUBLIC FUNCTIONS
	//////////////////////////////////////////////////////////////*/

	function initialize(
		address treasuryFeeRecipient_,
		address redistributionFeeRecipient_,
		address authorizer_,
		ISonaRewardToken _rewardTokenBase,
		ISplitMain _splitMain,
		address _eoaAdmin,
		IWETH weth_
	) public initializer {
		// Setup role for contract creator, otherwise subsequent checks will not work
		_setupRole(_ADMIN_ROLE, _eoaAdmin);
		_setRoleAdmin(_ADMIN_ROLE, _ADMIN_ROLE);

		treasuryFeeRecipient_.revertIfZero(
			SonaReserveAuction_InvalidAddress.selector
		);
		_treasuryFeeRecipient = treasuryFeeRecipient_;

		redistributionFeeRecipient_.revertIfZero(
			SonaReserveAuction_InvalidAddress.selector
		);
		_redistributionFeeRecipient = redistributionFeeRecipient_;

		authorizer_.revertIfZero(SonaReserveAuction_InvalidAddress.selector);
		_authorizer = authorizer_;

		_weth = weth_;

		splitMain = _splitMain;

		// Initialize the reward token. Admin is the auction
		rewardToken = ISonaRewardToken(
			address(
				new ERC1967Proxy(
					address(_rewardTokenBase),
					abi.encodeWithSelector(
						ISonaRewardToken.initialize.selector,
						"Sona Rewards Token",
						"RWRD",
						_eoaAdmin,
						address(this)
					)
				)
			)
		);

		_DOMAIN_SEPARATOR = keccak256(
			abi.encode(
				_EIP712DOMAIN_TYPEHASH,
				keccak256("SonaReserveAuction"), // name
				keccak256(abi.encodePacked(_getInitializedVersion() + uint8(48))), // version
				block.chainid, // chain ID
				address(this) // verifying contract
			)
		);
	}

	/// @notice Creates a new auction.
	/// @dev Creating a reserve auction does not start it.
	/// Auctions are started once a bid of the reserve price or higher is placed.
	/// @param _currencyAddress The address of the currency bids will be in.
	/// @param _reservePrice The reserve price of the auction.
	function createReserveAuction(
		ISonaRewardToken.TokenMetadatas calldata _metadata,
		Signature calldata _signature,
		address _currencyAddress,
		uint256 _reservePrice
	) external bundlesAuthorized(_metadata, _signature) {
		// Check that the reserve price is not zero. No free auctions
		if (_reservePrice == 0) {
			revert SonaReserveAuction_ReservePriceCannotBeZero();
		}
		if (auctions[_metadata.bundles[1].tokenId].reservePrice > 0)
			revert SonaReserveAuction_AlreadyListed();

		_ensureBundleIsUnique(_metadata.bundles[0]);
		_ensureBundleIsUnique(_metadata.bundles[1]);

		if (
			_metadata.bundles[0].tokenId % 2 != 0 ||
			_metadata.bundles[0].tokenId + 1 != _metadata.bundles[1].tokenId
		) revert SonaReserveAuction_InvalidTokenIds();

		auctions[_metadata.bundles[1].tokenId].reservePrice = _reservePrice;
		auctions[_metadata.bundles[1].tokenId].trackSeller = payable(
			_metadata.bundles[0].tokenId.getAddress()
		);

		// Note: If the currency address is 0x0/address(0), bids are made in ETH
		auctions[_metadata.bundles[1].tokenId].currency = _currencyAddress;
		auctions[_metadata.bundles[1].tokenId].tokenMetadata = _metadata.bundles[1];

		if (!rewardToken.tokenIdExists(_metadata.bundles[0].tokenId))
			rewardToken.mint(
				_metadata.bundles[0].tokenId.getAddress(),
				_metadata.bundles[0].tokenId,
				_metadata.bundles[0].arweaveTxId,
				_metadata.bundles[0].payout
			);

		emit ReserveAuctionCreated({ tokenId: _metadata.bundles[1].tokenId });
	}

	/// @dev Public function to settle the reseerve auction
	/// @param _tokenId The ID of the token.
	function settleReserveAuction(uint256 _tokenId) external {
		_settleReserveAuction(_tokenId);
	}

	/// @notice Settle the reserve auction and distribute a split
	/// @dev This function is secured on the Splits-side and will revert if the
	/// 			payout address is not a registered split
	/// @param _tokenId The ID of the token.
	/// @param _accounts The list of accounts in the configured split
	/// @param _percentAllocations The list of proportional amounts in the configured split
	function settleReserveAuctionAndDistributePayout(
		uint256 _tokenId,
		address[] calldata _accounts,
		uint32[] calldata _percentAllocations
	) external {
		address payout = auctions[_tokenId].tokenMetadata.payout;
		address currency = auctions[_tokenId].currency;
		_settleReserveAuction(_tokenId);
		if (currency.isZero()) {
			splitMain.distributeETH(payout, _accounts, _percentAllocations);
		} else {
			splitMain.distributeERC20(
				payout,
				IERC20(currency),
				_accounts,
				_percentAllocations
			);
		}
	}

	/// @dev Public function to cancel the reserve auction
	/// @param _tokenId The ID of the token.
	function cancelReserveAuction(
		uint256 _tokenId
	) external onlySonaAdminOrApprovedTokenOperator(_tokenId) {
		Auction storage auction = auctions[_tokenId];

		if (auction.reservePrice == 0) {
			revert SonaReserveAuction_InvalidAuction();
		}

		// Can't settle an auction that can still be bidded on
		if (auction.endingTime > block.timestamp) {
			revert SonaReserveAuction_AuctionIsLive();
		}

		// Can't cancel an auction that is finished but hasn't been settled
		if (auction.endingTime != 0 && auction.endingTime <= block.timestamp) {
			revert SonaReserveAuction_AuctionEnded();
		}

		delete auctions[_tokenId];

		emit ReserveAuctionCanceled({ tokenId: _tokenId });
	}

	/// @dev Public function to update the reserve price of the auction
	/// @param _tokenId The ID of the token.
	/// @param _reservePrice The reserve price to be updated to
	function updateReserveAuctionPrice(
		uint256 _tokenId,
		uint256 _reservePrice
	) external onlySonaAdminOrApprovedTokenOperator(_tokenId) {
		Auction storage auction = auctions[_tokenId];

		if (_reservePrice == 0) {
			revert SonaReserveAuction_ReservePriceCannotBeZero();
		}

		// Can't settle an auction that can still be bidded on
		if (auction.endingTime > block.timestamp) {
			revert SonaReserveAuction_AuctionIsLive();
		}

		auction.reservePrice = uint256(_reservePrice);

		emit ReserveAuctionPriceUpdated({ tokenId: _tokenId, auction: auction });
	}

	/// @dev Public function to update the curency and reserve price of the auction
	/// @param _currency The currency to be updated to
	/// @param _tokenId The ID of the token.
	/// @param _reservePrice The reserve price to be updated to
	function updateReserveAuctionPriceAndCurrency(
		address _currency,
		uint256 _tokenId,
		uint256 _reservePrice
	) external onlySonaAdminOrApprovedTokenOperator(_tokenId) {
		Auction storage auction = auctions[_tokenId];

		// Can't settle an auction that can still be bidded on
		if (auction.endingTime > block.timestamp) {
			revert SonaReserveAuction_AuctionIsLive();
		}

		if (_reservePrice == 0) {
			revert SonaReserveAuction_ReservePriceCannotBeZero();
		}

		auction.reservePrice = uint256(_reservePrice);
		auction.currency = _currency;

		emit ReserveAuctionPriceUpdated({ tokenId: _tokenId, auction: auction });
	}

	/// @notice set the payout address to `_payout` for auction with id `_tokenId`
	/// @dev setting the address to address(0) resets the payout address to the seller's address
	/// @param _tokenId The artist tokenId used as the identifier for the auction
	/// @param _payout The address to receive NFT sale proceeds and future reward claims
	function updateArtistPayoutAddress(
		uint256 _tokenId,
		address payable _payout
	) external onlySonaAdminOrApprovedTokenOperator(_tokenId) {
		Auction storage auction = auctions[_tokenId];

		if (auction.reservePrice == 0) {
			revert SonaReserveAuction_InvalidAuction();
		}

		auction.tokenMetadata.payout = _payout;

		emit PayoutAddressUpdated(_tokenId, _payout);
	}

	/// @dev Public function to bid on a reserve auction
	/// @param _tokenId The ID of the token.
	/// @param _bidAmount The amount of the bid if the currency is not ETH
	// solhint-disable-next-line code-complexity
	function createBid(uint256 _tokenId, uint256 _bidAmount) external payable {
		uint256 attemptedBid;

		// If the currency ETH, the bid amount is the msg.value
		// Else, the bid amount is the _bidAmount
		if (msg.value > 0) {
			attemptedBid = msg.value;
		} else {
			if (_bidAmount == 0) {
				revert SonaReserveAuction_BidTooLow();
			}

			attemptedBid = _bidAmount;
		}

		Auction storage auction = auctions[_tokenId];

		if (
			(msg.value > 0 && auction.currency.isNotZero()) ||
			(auction.currency.isZero() && msg.value == 0)
		) {
			revert SonaReserveAuction_InvalidCurrency();
		}

		// if reserve price is 0, auction has not been created
		if (auction.reservePrice == 0) {
			revert SonaReserveAuction_InvalidAuction();
		}

		// if attempted bid is less than the reserve price, revert
		if (attemptedBid < auction.reservePrice) {
			revert SonaReserveAuction_BidTooLow();
		}

		// get current ending time
		uint256 currentEndingTime = auction.endingTime;

		// if current ending time is 0, a bid has not been placed yet
		if (currentEndingTime == 0) {
			auction.currentBidder = payable(msg.sender);
			auction.currentBidAmount = attemptedBid;

			// transfer ERC20 bid amount to this contract
			if (auction.currency.isNotZero()) {
				if (
					!IERC20(auction.currency).transferFrom(
						msg.sender,
						address(this),
						attemptedBid
					)
				) revert SonaReserveAuction_TransferFailed();
			}

			unchecked {
				currentEndingTime = block.timestamp + _AUCTION_DURATION;
			}
			auction.endingTime = currentEndingTime;
			auction.currentBidder = payable(msg.sender);
			auction.currentBidAmount = attemptedBid;

			//  else, a bid has been placed
		} else {
			// if the ending time has passed, revert
			if (currentEndingTime < block.timestamp) {
				revert SonaReserveAuction_AuctionEnded();
				// if the ending time has not passed, continue with bid logic
			} else {
				// if the bid is higher than the current bid, refund the current bidder
				if (attemptedBid > auction.currentBidAmount) {
					address payable previousBidder = auction.currentBidder;
					uint256 previousBidAmount = auction.currentBidAmount;

					auction.currentBidder = payable(msg.sender);
					auction.currentBidAmount = attemptedBid;

					// Refund previous bidder
					_sendCurrencyToParticipant(
						previousBidder,
						previousBidAmount,
						auction.currency
					);

					// transfer bid amount to this contract
					if (auction.currency.isNotZero()) {
						if (
							!IERC20(auction.currency).transferFrom(
								msg.sender,
								address(this),
								auction.currentBidAmount
							)
						) revert SonaReserveAuction_TransferFailed();
					}

					// if the bid is lower than the current bid, revert
				} else {
					revert SonaReserveAuction_BidTooLow();
				}
			}
		}

		emit ReserveAuctionBidPlaced({ tokenId: _tokenId, amount: attemptedBid });
	}

	/// @dev Public function to fetch an auction
	/// @param _tokenId The ID of the token.
	function getAuction(uint256 _tokenId) external view returns (Auction memory) {
		return auctions[_tokenId];
	}

	/*//////////////////////////////////////////////////////////////
	/                    PRIVATE FUNCTIONS
	//////////////////////////////////////////////////////////////*/

	/*
	function _verify(
		ISonaRewardToken.TokenMetadata calldata _bundle,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal view returns (bool valid) {
		return _recoverAddress(_bundle, v, r, s) == _authorizer;
	}

	function _recoverAddress(
		ISonaRewardToken.TokenMetadata calldata _bundle,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal view returns (address recovered) {
		// Note: we need to use `encodePacked` here instead of `encode`.
		bytes32 digest = keccak256(
			abi.encodePacked("\x19\x01", _DOMAIN_SEPARATOR, _hash(_bundle))
		);
		recovered = ecrecover(digest, v, r, s);
	}

	function _hash(
		ISonaRewardToken.TokenMetadata calldata bundle
	) internal pure returns (bytes32) {
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
	*/

	/// @dev Internal function to settle the reserve auction
	/// @param _tokenId The ID of the token.
	function _settleReserveAuction(uint256 _tokenId) private {
		Auction storage auction = auctions[_tokenId];

		if (auction.reservePrice == 0) {
			revert SonaReserveAuction_InvalidAuction();
		}

		// Can't settle an auction that can still be bidded on
		if (auction.endingTime > block.timestamp) {
			revert SonaReserveAuction_AuctionIsLive();
		}

		// reduce sloads
		address currency = auction.currency;

		// Mint reward token to buyer
		rewardToken.mint(
			auction.currentBidder,
			_tokenId,
			auction.tokenMetadata.arweaveTxId,
			// the tokenMetadata payout address is set for auction proceeds, not for the collector.
			// Therefore, this address is set as zero.
			payable(address(0))
		);

		// Send redistribution fee to the redistribution fee recipient

		uint256 redistributionFeeAmount;
		uint256 treasuryFeeAmount;
		uint256 sellerProceedsAmount;
		uint256 totalFeesAmount;
		// solhint-disable-next-line no-inline-assembly
		assembly {
			// currentBidAmount needs an offset as it's the 3rd variable in the struct
			let currentBidAmountPointer := add(auction.slot, 2)

			// Load the currentBidAmount
			let currentBidAmount := sload(currentBidAmountPointer)

			// prevent div by 0
			if gt(currentBidAmount, 0) {
				// Calculate the redistribution fee amount
				redistributionFeeAmount := div(
					mul(currentBidAmount, _AUCTION_REDISTRIBUTION_FEE_BPS),
					10000
				)

				// Calculate the treasury fee amount
				treasuryFeeAmount := div(
					mul(currentBidAmount, _AUCTION_TREASURY_FEE_BPS),
					10000
				)

				// Total fees
				totalFeesAmount := add(redistributionFeeAmount, treasuryFeeAmount)

				// Calculate the seller proceeds amount
				sellerProceedsAmount := sub(currentBidAmount, totalFeesAmount)
			}
		}

		// Send the currency to the treasury fee recipient
		_handleTokenTransfer(_treasuryFeeRecipient, treasuryFeeAmount, currency);

		// Send the currency to the redistribution fee recipient
		_handleTokenTransfer(
			_redistributionFeeRecipient,
			redistributionFeeAmount,
			currency
		);

		// Send the currency to the seller or the seller's delegated address
		address payable payoutAddress = _getPayoutAddress(auction.tokenMetadata);
		_sendCurrencyToParticipant(payoutAddress, sellerProceedsAmount, currency);

		// Remove from map
		delete auctions[_tokenId];

		emit ReserveAuctionSettled({ tokenId: _tokenId });
	}

	function _ensureBundleIsUnique(
		ISonaRewardToken.TokenMetadata calldata _bundle
	) internal {
		if (
			_uriExists[keccak256(bytes(_bundle.arweaveTxId))] ||
			rewardToken.tokenIdExists(_bundle.tokenId)
		) revert SonaReserveAuction_Duplicate();
		_uriExists[keccak256(bytes(_bundle.arweaveTxId))] = true;
	}

	function _handleTokenTransfer(
		address _to,
		uint256 _amount,
		address _currency
	) internal {
		if (_currency.isZero()) {
			_wrapAndSendEth(_to, _amount);
		} else {
			// Send currency
			_transferTokenOut(_to, _amount, _currency);
		}
	}

	function _sendCurrencyToParticipant(
		address payable _to,
		uint256 _amount,
		address _currency
	) internal {
		if (_currency.isZero()) {
			if (!_to.send(_amount)) {
				_wrapAndSendEth(_to, _amount);
			}
		} else {
			// Send currency
			_transferTokenOut(_to, _amount, _currency);
		}
	}

	function _wrapAndSendEth(address _to, uint256 _amount) internal {
		// Wrap refund in weth
		_weth.deposit{ value: _amount }();
		// Send weth
		_transferTokenOut(_to, _amount, address(_weth));
	}

	function _transferTokenOut(
		address _to,
		uint256 _amount,
		address _currency
	) internal {
		if (!IERC20(_currency).transfer(_to, _amount))
			revert SonaReserveAuction_TransferFailed();
	}

	function _getPayoutAddress(
		ISonaRewardToken.TokenMetadata storage _bundle
	) internal view returns (address payable payoutAddress) {
		address payable payout = _bundle.payout;
		return payout.isNotZero() ? payout : payable(_bundle.tokenId.getAddress());
	}
}
