// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { ISplitMain } from "../../payout/interfaces/ISplitMain.sol";
import { ISonaAuthorizer } from "../../interfaces/ISonaAuthorizer.sol";
import { SplitMain } from "../../payout/SplitMain.sol";
import { SplitWallet } from "../../payout/SplitWallet.sol";
import { Util } from "../Util.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { MockERC20 } from "../../../lib/solady/test/utils/mocks/MockERC20.sol";

// import "forge-std/console.sol";

contract SonaTestSplits is Util, ISonaAuthorizer {
	SplitMain public splitMain;
	address public split;
	// derived from ../../scripts/signTyped.ts
	string public mnemonic =
		"test test test test test test test test test test test junk";
	uint256 public authorizerKey = vm.deriveKey(mnemonic, 0);
	address public authorizer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

	address public account1 = makeAddr("account1");
	address public account2 = makeAddr("account2");
	MockERC20 public mockERC20 = new MockERC20("Mock Token", "USDC", 6);

	event UpdateSplit(address indexed split);

	function setUp() public {
		splitMain = new SplitMain(authorizer);
	}

	function test_UpdateSplit() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		Signature memory sig = _signSplitConfig(split, accounts, amounts);

		vm.expectEmit(true, false, false, false, address(splitMain));
		emit UpdateSplit(address(split));
		hoax(account1);
		splitMain.updateSplit(split, accounts, amounts, sig);
	}

	function test_revertUpdateSplitUnauthorized() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		Signature memory sig = _signSplitConfig(split, accounts, amounts);

		vm.expectRevert(
			abi.encodeWithSelector(SplitMain.Unauthorized.selector, address(3))
		);
		hoax(address(3));
		splitMain.updateSplit(split, accounts, amounts, sig);
	}

	function test_distributeERC20ToEOA() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		hoax(address(0));
		mockERC20.mint(split, 1e8);

		uint initialBalance2 = mockERC20.balanceOf(account2);
		uint initialBalance1 = mockERC20.balanceOf(account1);

		splitMain.distributeERC20(
			split,
			IERC20(address(mockERC20)),
			accounts,
			amounts
		);

		uint finalBalance2 = mockERC20.balanceOf(account2);
		uint finalBalance1 = mockERC20.balanceOf(account1);
		assertEq(finalBalance2 - initialBalance2, 1e8 / 2 - 1);
		assertEq(finalBalance1 - initialBalance1, 1e8 / 2 - 1);
	}

	function test_distributeERC20ToContracts() public {
		(
			address[] memory accounts,
			uint32[] memory amounts
		) = _createSimpleNonReceiverSplit();
		hoax(address(0));
		mockERC20.mint(split, 1e8);

		uint initialBalance2 = mockERC20.balanceOf(accounts[0]);
		uint initialBalance1 = mockERC20.balanceOf(accounts[1]);

		splitMain.distributeERC20(
			split,
			IERC20(address(mockERC20)),
			accounts,
			amounts
		);

		uint finalBalance2 = mockERC20.balanceOf(accounts[0]);
		uint finalBalance1 = mockERC20.balanceOf(accounts[1]);
		assertEq(finalBalance2 - initialBalance2, 1e8 / 2 - 1);
		assertEq(finalBalance1 - initialBalance1, 1e8 / 2 - 1);
	}

	function test_distributeETHToEOA() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		hoax(address(0));
		payable(split).transfer(10 ether);

		uint initialBalance2 = account2.balance;
		uint initialBalance1 = account1.balance;

		splitMain.distributeETH(split, accounts, amounts);

		uint finalBalance2 = account2.balance;
		uint finalBalance1 = account1.balance;
		assertEq(finalBalance2 - initialBalance2, 10 ether / 2);
		assertEq(finalBalance1 - initialBalance1, 10 ether / 2);
	}

	function test_distributeETHToNonReceivingContracts() public {
		(
			address[] memory accounts,
			uint32[] memory amounts
		) = _createSimpleNonReceiverSplit();
		hoax(address(0));
		payable(split).transfer(10 ether);

		uint initialBalance2 = accounts[0].balance;
		uint initialBalance1 = accounts[1].balance;

		splitMain.distributeETH(split, accounts, amounts);

		uint finalBalance2 = accounts[0].balance;
		uint finalBalance1 = accounts[1].balance;
		assertEq(finalBalance2 - initialBalance2, 0);
		assertEq(finalBalance1 - initialBalance1, 0);
	}

	// TODO add check to ensure invalid signatures revert

	function _createSimpleSplit()
		private
		returns (address[] memory accounts, uint32[] memory amounts)
	{
		accounts = new address[](2);
		accounts[0] = account2;
		accounts[1] = account1;

		amounts = new uint32[](2);
		amounts[0] = 5e5;
		amounts[1] = 5e5;
		_createSplit(accounts, amounts);
	}

	function _createSimpleNonReceiverSplit()
		private
		returns (address[] memory accounts, uint32[] memory amounts)
	{
		accounts = new address[](2);
		accounts[1] = address(new NonReceiver());
		accounts[0] = address(new NonReceiver());

		amounts = new uint32[](2);
		amounts[0] = 5e5;
		amounts[1] = 5e5;
		_createSplit(accounts, amounts);
	}

	function _signSplitConfig(
		address _split,
		address[] memory _accounts,
		uint32[] memory _percentAllocations
	) private view returns (Signature memory signature) {
		bytes32 splitConfigHash = _getSplitConfigHash(
			_split,
			_accounts,
			_percentAllocations
		);

		(uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerKey, splitConfigHash);

		return Signature({ v: v, r: r, s: s });
	}

	function _createSplit(
		address[] memory accounts,
		uint32[] memory percents
	) internal {
		require(
			accounts.length == percents.length,
			"_createSplit: array length mismatch"
		);
		uint256 amountSum = 0;
		for (uint8 i = 0; i < percents.length; ++i) {
			amountSum += percents[i];
		}
		require(amountSum == 1e6, "_createSplit: percents dont add to 100");
		split = splitMain.createSplit(accounts, percents);
	}

	function _getSplitConfigHash(
		address _split,
		address[] memory _accounts,
		uint32[] memory _percentAllocations
	) private view returns (bytes32) {
		bytes32 domainSeparator = _makeDomainHash();
		return
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					domainSeparator,
					_hashFromMemory(_split, _accounts, _percentAllocations)
				)
			);
	}

	function _makeDomainHash() private view returns (bytes32) {
		bytes32 _EIP712DOMAIN_TYPEHASH = keccak256(
			"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
		);
		return
			keccak256(
				abi.encode(
					_EIP712DOMAIN_TYPEHASH,
					keccak256("SplitMain"), // name
					keccak256("1"), // version
					block.chainid, // chain ID
					address(splitMain) // verifying contract
				)
			);
	}

	function _hashFromMemory(
		address _split,
		address[] memory _accounts,
		uint32[] memory _percentAllocations
	) internal pure returns (bytes32) {
		bytes32 _SPLIT_TYPEHASH = keccak256(
			"SplitConfig(address split,address[] accounts,uint32[] percentAllocations)"
		);
		return
			keccak256(
				abi.encode(
					_SPLIT_TYPEHASH,
					_split,
					keccak256(abi.encodePacked(_accounts)),
					keccak256(abi.encodePacked(_percentAllocations))
				)
			);
	}
}

// solhint-disable-next-line no-empty-blocks
contract NonReceiver {

}
