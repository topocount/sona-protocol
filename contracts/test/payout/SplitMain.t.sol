// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { ISplitMain } from "../../payout/interfaces/ISplitMain.sol";
import { ISonaAuthorizer } from "../../interfaces/ISonaAuthorizer.sol";
import { SplitMain } from "../../payout/SplitMain.sol";
import { SplitWallet } from "../../payout/SplitWallet.sol";
import { Util } from "../Util.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

// import "forge-std/console.sol";

contract SonaTestSplits is Util, ISonaAuthorizer {
	SplitMain public splitMain;
	address public split;
	// derived from ../../scripts/signTyped.ts
	string public mnemonic =
		"test test test test test test test test test test test junk";
	uint256 public authorizerKey = vm.deriveKey(mnemonic, 0);
	address public authorizer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

	event UpdateSplit(address indexed split);

	function setUp() public {
		splitMain = new SplitMain(authorizer);
	}

	function test_UpdateSplit() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		Signature memory sig = _signSplitConfig(split, accounts, amounts);

		vm.expectEmit(true, false, false, false, address(splitMain));
		emit UpdateSplit(address(split));
		hoax(address(1));
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

	function test_distributeETH() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		hoax(address(0));
		payable(split).transfer(10 ether);

		splitMain.distributeETH(split, accounts, amounts);

		IERC20[] memory emptyERC20s = new IERC20[](0);

		uint initialBalance = address(1).balance;
		splitMain.withdraw(address(1), 1, emptyERC20s);
		splitMain.withdraw(address(2), 1, emptyERC20s);
		uint finalBalance = address(1).balance;
		assertEq(finalBalance - initialBalance, 4999999999999999999);
	}

	// TODO add check to ensure invalid signatures revert

	function _createSimpleSplit()
		private
		returns (address[] memory accounts, uint32[] memory amounts)
	{
		accounts = new address[](2);
		accounts[0] = address(1);
		accounts[1] = address(2);

		amounts = new uint32[](2);
		amounts[0] = 5e5;
		amounts[1] = 5e5;
		split = splitMain.createSplit(accounts, amounts);
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
