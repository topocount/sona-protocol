// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import { ISplitMain } from "./interfaces/ISplitMain.sol";
import { SplitWallet } from "./SplitWallet.sol";
import { Clones } from "../utils/Clones.sol";
// TODO convert ERC20 to IERC20 to save some gas
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

/// @title SplitMain
/// @author 0xSplits <will@0xSplits.xyz>
/// @notice A composable and gas-efficient protocol for deploying splitter contracts.
/// @dev Split recipients, ownerships, and keeper fees are stored onchain as calldata & re-passed as args / validated
/// via hashing when needed. Each split gets its own address & proxy for maximum composability with other contracts onchain.
/// For these proxies, we extended EIP-1167 Minimal Proxy Contract to avoid `DELEGATECALL` inside `receive()` to accept
/// hard gas-capped `sends` & `transfers`.
contract SplitMain is ISplitMain {
	using SafeTransferLib for address;

	/// ERRORS

	/// @notice Unauthorized sender `sender`
	/// @param sender Transaction sender
	error Unauthorized(address sender);
	/// @notice Invalid number of accounts `accountsLength`, must have at least 2
	/// @param accountsLength Length of accounts array
	error InvalidSplit__TooFewAccounts(uint256 accountsLength);
	/// @notice Array lengths of accounts & percentAllocations don't match (`accountsLength` != `allocationsLength`)
	/// @param accountsLength Length of accounts array
	/// @param allocationsLength Length of percentAllocations array
	error InvalidSplit__AccountsAndAllocationsMismatch(
		uint256 accountsLength,
		uint256 allocationsLength
	);
	/// @notice Invalid percentAllocations sum `allocationsSum` must equal `PERCENTAGE_SCALE`
	/// @param allocationsSum Sum of percentAllocations array
	error InvalidSplit__InvalidAllocationsSum(uint32 allocationsSum);
	/// @notice Invalid accounts ordering at `index`
	/// @param index Index of out-of-order account
	error InvalidSplit__AccountsOutOfOrder(uint256 index);
	/// @notice Invalid percentAllocation of zero at `index`
	/// @param index Index of zero percentAllocation
	error InvalidSplit__AllocationMustBePositive(uint256 index);
	/// @notice Invalid distributorFee `distributorFee` cannot be greater than 10% (1e5)
	/// @param distributorFee Invalid distributorFee amount
	error InvalidSplit__InvalidDistributorFee(uint32 distributorFee);
	/// @notice Invalid hash `hash` from split data (accounts, percentAllocations, distributorFee)
	/// @param hash Invalid hash
	error InvalidSplit__InvalidHash(bytes32 hash);
	/// @notice Invalid new controlling address `newController` for mutable split
	/// @param newController Invalid new controller
	error InvalidNewController(address newController);

	//
	// STRUCTS
	//

	/// @notice holds Split metadata
	struct Split {
		bytes32 hash;
		address[] controllers;
	}

	//
	// Storage
	//

	//
	// STORAGE - CONSTANTS & IMMUTABLES
	//

	/// @notice constant to scale uints into percentages (1e6 == 100%)
	uint256 public constant PERCENTAGE_SCALE = 1e6;
	/// @notice maximum distributor fee; 1e5 = 10%/// PERCENTAGE_SCALE
	uint256 internal constant _MAX_DISTRIBUTOR_FEE = 1e5;
	/// @notice address of wallet implementation for split proxies
	address public immutable override walletImplementation;
	// @dev The signature of the Domain separator typehash
	bytes32 private constant _EIP712DOMAIN_TYPEHASH =
		keccak256(
			"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
		);
	// @dev The signature of the type that is hashed and prefixed to the TypedData payload
	bytes32 private constant _SPLIT_TYPEHASH =
		keccak256(
			"SplitConfig(address split,address[] accounts,uint32[] percentAllocations)"
		);

	//
	// STORAGE - VARIABLES - PRIVATE & INTERNAL
	//

	/// @notice mapping to account ETH balances
	mapping(address => uint256) internal _ethBalances;
	/// @notice mapping to account ERC20 balances
	mapping(IERC20 => mapping(address => uint256)) internal _erc20Balances;
	/// @notice mapping to Split metadata
	mapping(address => Split) internal _splits;
	/// @dev part of the EIP-712 standard for structured data hashes
	bytes32 private _DOMAIN_SEPARATOR;
	/// @dev the address of the authorizing signer
	address private _authorizer;

	//
	// MODIFIERS
	//

	modifier checkUpdateSignature(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations,
		Signature calldata sig
	) {
		if (!_verify(split, accounts, percentAllocations, sig.v, sig.r, sig.s))
			revert SonaAuthorizer_InvalidSignature();

		_;
	}

	/// @notice Reverts if the sender doesn't own the split `split`
	/// @param split Address to check for control
	modifier onlySplitController(address split) {
		if (!_isController(split, msg.sender)) revert Unauthorized(msg.sender);
		_;
	}

	/// @notice Reverts if the split with recipients represented by `accounts` and `percentAllocations` is malformed
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	modifier validSplit(
		address[] memory accounts,
		uint32[] memory percentAllocations
	) {
		if (accounts.length < 2)
			revert InvalidSplit__TooFewAccounts(accounts.length);
		if (accounts.length != percentAllocations.length)
			revert InvalidSplit__AccountsAndAllocationsMismatch(
				accounts.length,
				percentAllocations.length
			);
		// _getSum should overflow if any percentAllocation[i] < 0
		if (_getSum(percentAllocations) != PERCENTAGE_SCALE)
			revert InvalidSplit__InvalidAllocationsSum(_getSum(percentAllocations));
		unchecked {
			// overflow should be impossible in for-loop index
			// cache accounts length to save gas
			uint256 loopLength = accounts.length - 1;
			for (uint256 i = 0; i < loopLength; ++i) {
				// overflow should be impossible in array access math
				if (accounts[i] >= accounts[i + 1])
					revert InvalidSplit__AccountsOutOfOrder(i);
				if (percentAllocations[i] == uint32(0))
					revert InvalidSplit__AllocationMustBePositive(i);
			}
			// overflow should be impossible in array access math with validated equal array lengths
			if (percentAllocations[loopLength] == uint32(0))
				revert InvalidSplit__AllocationMustBePositive(loopLength);
		}
		_;
	}

	// CONSTRUCTOR

	constructor(address authorizer_) {
		walletImplementation = address(new SplitWallet());
		_authorizer = authorizer_;

		_DOMAIN_SEPARATOR = keccak256(
			abi.encode(
				_EIP712DOMAIN_TYPEHASH,
				keccak256("SplitMain"), // name
				keccak256("1"), // version
				block.chainid, //chain ID
				address(this)
			)
		);
	}

	// FUNCTIONS

	// FUNCTIONS - PUBLIC & EXTERNAL

	/// @notice Receive ETH
	/// @dev Used by split proxies in `distributeETH` to transfer ETH to `SplitMain`
	///		Funds sent outside of `distributeETH` will be unrecoverable
	receive() external payable {} // solhint-disable-line no-empty-blocks

	// TODO gate this on SonaAdmin
	/// @notice Creates a new split with recipients `accounts` with ownerships `percentAllocations`, a keeper fee for splitting of `distributorFee` and the controlling address `controller`
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	/// @return split Address of newly created split
	function createSplit(
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	)
		external
		override
		validSplit(accounts, percentAllocations)
		returns (address split)
	{
		bytes32 splitHash = _hashSplit(accounts, percentAllocations);
		// create mutable split
		split = Clones.clone(walletImplementation);
		_splits[split].controllers = accounts;
		// store split's hash in storage for future verification
		_splits[split].hash = splitHash;
		emit CreateSplit(split);
	}

	/// @notice Updates an existing split with recipients `accounts` with ownerships `percentAllocations` and a keeper fee for splitting of `distributorFee`
	/// @param split Address of mutable split to update
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	function updateSplit(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations,
		Signature calldata sig
	)
		external
		override
		checkUpdateSignature(split, accounts, percentAllocations, sig)
		onlySplitController(split)
		validSplit(accounts, percentAllocations)
	{
		_updateSplit(split, accounts, percentAllocations);
	}

	/// @notice Distributes the ETH balance for split `split`
	/// @dev `accounts`, `percentAllocations`, and `distributorFee` are verified by hashing
	/// & comparing to the hash in storage associated with split `split`
	/// @param split Address of split to distribute balance for
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	function distributeETH(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) external override validSplit(accounts, percentAllocations) {
		// use internal fn instead of modifier to avoid stack depth compiler errors
		_validSplitHash(split, accounts, percentAllocations);
		_distributeETH(split, accounts, percentAllocations);
	}

	/// @notice Updates & distributes the ETH balance for split `split`
	/// @dev only callable by SplitController
	/// @param split Address of split to distribute balance for
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	function updateAndDistributeETH(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations,
		Signature calldata sig
	)
		external
		override
		checkUpdateSignature(split, accounts, percentAllocations, sig)
		onlySplitController(split)
		validSplit(accounts, percentAllocations)
	{
		_updateSplit(split, accounts, percentAllocations);
		// know splitHash is valid immediately after updating; only accessible via controller
		_distributeETH(split, accounts, percentAllocations);
	}

	/// @notice Distributes the ERC20 `token` balance for split `split`
	/// @dev `accounts`, `percentAllocations`, and `distributorFee` are verified by hashing
	/// & comparing to the hash in storage associated with split `split`
	/// @dev pernicious ERC20s may cause overflow in this function inside
	/// _scaleAmountByPercentage, but results do not affect ETH & other ERC20 balances
	/// @param split Address of split to distribute balance for
	/// @param token Address of ERC20 to distribute balance for
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	function distributeERC20(
		address split,
		IERC20 token,
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) external override validSplit(accounts, percentAllocations) {
		// use internal fn instead of modifier to avoid stack depth compiler errors
		_validSplitHash(split, accounts, percentAllocations);
		_distributeERC20(split, token, accounts, percentAllocations);
	}

	/// @notice Updates & distributes the ERC20 `token` balance for split `split`
	/// @dev only callable by SplitController
	/// @dev pernicious ERC20s may cause overflow in this function inside
	/// _scaleAmountByPercentage, but results do not affect ETH & other ERC20 balances
	/// @param split Address of split to distribute balance for
	/// @param token Address of ERC20 to distribute balance for
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	function updateAndDistributeERC20(
		address split,
		IERC20 token,
		address[] calldata accounts,
		uint32[] calldata percentAllocations,
		Signature calldata sig
	)
		external
		override
		onlySplitController(split)
		validSplit(accounts, percentAllocations)
		checkUpdateSignature(split, accounts, percentAllocations, sig)
	{
		_updateSplit(split, accounts, percentAllocations);
		// know splitHash is valid immediately after updating; only accessible via controller
		_distributeERC20(split, token, accounts, percentAllocations);
	}

	/// @notice Withdraw ETH &/ ERC20 balances for account `account`
	/// @param account Address to withdraw on behalf of
	/// @param withdrawETH Withdraw all ETH if nonzero
	/// @param tokens Addresses of ERC20s to withdraw
	function withdraw(
		address account,
		uint256 withdrawETH,
		IERC20[] calldata tokens
	) external override {
		uint256[] memory tokenAmounts = new uint256[](tokens.length);
		uint256 ethAmount;
		if (withdrawETH != 0) {
			ethAmount = _withdraw(account);
		}
		unchecked {
			// overflow should be impossible in for-loop index
			for (uint256 i = 0; i < tokens.length; ++i) {
				// overflow should be impossible in array length math
				tokenAmounts[i] = _withdrawERC20(account, tokens[i]);
			}
			emit Withdrawal(account, ethAmount, tokens, tokenAmounts);
		}
	}

	/// FUNCTIONS - VIEWS

	/// @notice Returns the current hash of split `split`
	/// @param split Split to return hash for
	/// @return Split's hash
	function getHash(address split) external view returns (bytes32) {
		return _splits[split].hash;
	}

	/// @notice Returns the current controllers of split `split`
	/// @param split Split to return controller for
	/// @return controllers Split's controller list
	function getControllers(
		address split
	) external view returns (address[] memory controllers) {
		return _splits[split].controllers;
	}

	/// @notice Returns the current ETH balance of account `account`
	/// @param account Account to return ETH balance for
	/// @return Account's balance of ETH
	function getETHBalance(address account) external view returns (uint256) {
		return
			_ethBalances[account] +
			(_splits[account].hash != 0 ? account.balance : 0);
	}

	/// @notice Returns the ERC20 balance of token `token` for account `account`
	/// @param account Account to return ERC20 `token` balance for
	/// @param token Token to return balance for
	/// @return Account's balance of `token`
	function getERC20Balance(
		address account,
		IERC20 token
	) external view returns (uint256) {
		return
			_erc20Balances[token][account] +
			(_splits[account].hash != 0 ? token.balanceOf(account) : 0);
	}

	/// FUNCTIONS - PRIVATE & INTERNAL

	/// @notice Sums array of uint32s
	/// @param numbers Array of uint32s to sum
	/// @return sum Sum of `numbers`.
	function _getSum(uint32[] memory numbers) internal pure returns (uint32 sum) {
		// overflow should be impossible in for-loop index
		uint256 numbersLength = numbers.length;
		for (uint256 i = 0; i < numbersLength; ) {
			sum += numbers[i];
			unchecked {
				// overflow should be impossible in for-loop index
				++i;
			}
		}
	}

	/// @notice Hashes a split
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	/// @return computedHash Hash of the split.
	function _hashSplit(
		address[] memory accounts,
		uint32[] memory percentAllocations
	) internal pure returns (bytes32) {
		return keccak256(abi.encodePacked(accounts, percentAllocations));
	}

	/// @notice Updates an existing split with recipients `accounts` with ownerships `percentAllocations` and a keeper fee for splitting of `distributorFee`
	/// @param split Address of mutable split to update
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	function _updateSplit(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) internal {
		bytes32 splitHash = _hashSplit(accounts, percentAllocations);
		// store new hash in storage for future verification
		_splits[split].hash = splitHash;
		emit UpdateSplit(split);
	}

	/// @notice Checks hash from `accounts`, `percentAllocations` against the hash stored for `split`
	/// @param split Address of hash to check
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	function _validSplitHash(
		address split,
		address[] memory accounts,
		uint32[] memory percentAllocations
	) internal view {
		bytes32 hash = _hashSplit(accounts, percentAllocations);
		if (_splits[split].hash != hash) revert InvalidSplit__InvalidHash(hash);
	}

	function _isController(
		address split,
		address caller
	) internal view returns (bool) {
		address[] memory controllers = _splits[split].controllers;
		uint256 length = controllers.length;
		unchecked {
			for (uint i = 0; i < length; i++) {
				if (controllers[i] == caller) return true;
			}
		}
		return false;
	}

	/// @notice Distributes the ETH balance for split `split`
	/// @dev `accounts`, `percentAllocations`, and `distributorFee` must be verified before calling
	/// @param split Address of split to distribute balance for
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	function _distributeETH(
		address split,
		address[] memory accounts,
		uint32[] memory percentAllocations
	) internal {
		uint256 mainBalance = _ethBalances[split];
		uint256 proxyBalance = split.balance;
		// if mainBalance is positive, leave 1 in SplitMain for gas efficiency
		uint256 amountToSplit;
		unchecked {
			// underflow should be impossible
			if (mainBalance > 0) mainBalance -= 1;
			// overflow should be impossible
			amountToSplit = mainBalance + proxyBalance;
		}
		if (mainBalance > 0) _ethBalances[split] = 1;
		// emit event with gross amountToSplit
		emit DistributeETH(split, amountToSplit);
		unchecked {
			// distribute remaining balance
			// overflow should be impossible in for-loop index
			// cache accounts length to save gas
			uint256 accountsLength = accounts.length;
			for (uint256 i = 0; i < accountsLength; ++i) {
				// overflow should be impossible with validated allocations
				_ethBalances[accounts[i]] += _scaleAmountByPercentage(
					amountToSplit,
					percentAllocations[i]
				);
			}
		}
		// flush proxy ETH balance to SplitMain
		// split proxy should be guaranteed to exist at this address after validating splitHash
		// (attacker can't deploy own contract to address with high balance & empty sendETHToMain
		// to drain ETH from SplitMain)
		// could technically check if (change in proxy balance == change in SplitMain balance)
		// before/after external call, but seems like extra gas for no practical benefit
		if (proxyBalance > 0) SplitWallet(split).sendETHToMain(proxyBalance);
	}

	/// @notice Distributes the ERC20 `token` balance for split `split`
	/// @dev `accounts`, `percentAllocations`, and `distributorFee` must be verified before calling
	/// @dev pernicious ERC20s may cause overflow in this function inside
	/// _scaleAmountByPercentage, but results do not affect ETH & other ERC20 balances
	/// @param split Address of split to distribute balance for
	/// @param token Address of ERC20 to distribute balance for
	/// @param accounts Ordered, unique list of addresses with ownership in the split
	/// @param percentAllocations Percent allocations associated with each address
	function _distributeERC20(
		address split,
		IERC20 token,
		address[] memory accounts,
		uint32[] memory percentAllocations
	) internal {
		uint256 amountToSplit;
		uint256 mainBalance = _erc20Balances[token][split];
		uint256 proxyBalance = token.balanceOf(split);
		unchecked {
			// if mainBalance &/ proxyBalance are positive, leave 1 for gas efficiency
			// underflow should be impossible
			if (proxyBalance > 0) proxyBalance -= 1;
			// underflow should be impossible
			if (mainBalance > 0) {
				mainBalance -= 1;
			}
			// overflow should be impossible
			amountToSplit = mainBalance + proxyBalance;
		}
		if (mainBalance > 0) _erc20Balances[token][split] = 1;
		// emit event with gross amountToSplit (before deducting distributorFee)
		emit DistributeERC20(split, token, amountToSplit);
		// distribute remaining balance
		// overflows should be impossible in for-loop with validated allocations
		unchecked {
			// cache accounts length to save gas
			uint256 accountsLength = accounts.length;
			for (uint256 i = 0; i < accountsLength; ++i) {
				_erc20Balances[token][accounts[i]] += _scaleAmountByPercentage(
					amountToSplit,
					percentAllocations[i]
				);
			}
		}
		// split proxy should be guaranteed to exist at this address after validating splitHash
		// (attacker can't deploy own contract to address with high ERC20 balance & empty
		// sendERC20ToMain to drain ERC20 from SplitMain)
		// doesn't support rebasing or fee-on-transfer tokens
		// flush extra proxy ERC20 balance to SplitMain
		if (proxyBalance > 0)
			SplitWallet(split).sendERC20ToMain(token, proxyBalance);
	}

	/// @notice Multiplies an amount by a scaled percentage
	/// @param amount Amount to get `scaledPercentage` of
	/// @param scaledPercent Percent scaled by PERCENTAGE_SCALE
	/// @return scaledAmount Percent of `amount`.
	function _scaleAmountByPercentage(
		uint256 amount,
		uint256 scaledPercent
	) internal pure returns (uint256 scaledAmount) {
		// use assembly to bypass checking for overflow & division by 0
		// scaledPercent has been validated to be < PERCENTAGE_SCALE)
		// & PERCENTAGE_SCALE will never be 0
		// pernicious ERC20s may cause overflow, but results do not affect ETH & other ERC20 balances

		// solhint-disable-next-line no-inline-assembly
		assembly ("memory-safe") {
			/* eg (100/// 2*1e4) / (1e6) */
			scaledAmount := div(mul(amount, scaledPercent), PERCENTAGE_SCALE)
		}
	}

	/// @notice Withdraw ETH for account `account`
	/// @param account Account to withdrawn ETH for
	/// @return withdrawn Amount of ETH withdrawn
	function _withdraw(address account) internal returns (uint256 withdrawn) {
		// leave balance of 1 for gas efficiency
		// underflow if ethBalance is 0
		withdrawn = _ethBalances[account] - 1;
		_ethBalances[account] = 1;
		account.safeTransferETH(withdrawn);
	}

	/// @notice Withdraw ERC20 `token` for account `account`
	/// @param account Account to withdrawn ERC20 `token` for
	/// @return withdrawn Amount of ERC20 `token` withdrawn
	function _withdrawERC20(
		address account,
		IERC20 token
	) internal returns (uint256 withdrawn) {
		// leave balance of 1 for gas efficiency
		// underflow if erc20Balance is 0
		withdrawn = _erc20Balances[token][account] - 1;
		_erc20Balances[token][account] = 1;
		// TODO make safe
		token.transfer(account, withdrawn);
	}

	function _verify(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal view returns (bool valid) {
		return
			_recoverAddress(split, accounts, percentAllocations, v, r, s) ==
			_authorizer;
	}

	function _recoverAddress(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal view returns (address recovered) {
		// Note: we need to use `encodePacked` here instead of `encode`.
		bytes32 digest = keccak256(
			abi.encodePacked(
				"\x19\x01",
				_DOMAIN_SEPARATOR,
				_hashSplitConfig(split, accounts, percentAllocations)
			)
		);
		recovered = ecrecover(digest, v, r, s);
	}

	function _hashSplitConfig(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) internal pure returns (bytes32) {
		return
			keccak256(
				abi.encode(
					_SPLIT_TYPEHASH,
					split,
					keccak256(abi.encodePacked(accounts)),
					keccak256(abi.encodePacked(percentAllocations))
				)
			);
	}
}
