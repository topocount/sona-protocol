// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { ISplitMain } from "../../payout/interfaces/ISplitMain.sol";
import { SplitMain } from "../../payout/SplitMain.sol";
import { SplitWallet } from "../../payout/SplitWallet.sol";
import { MinterSigner } from "./MinterSigner.sol";
import { SonaReserveAuction } from "../../SonaReserveAuction.sol";
import { Util } from "../Util.sol";
import { MockERC20 } from "../../../lib/solady/test/utils/mocks/MockERC20.sol";

contract SplitHelpers is Util, SonaReserveAuction {
	SplitMain public splitMainImpl;
	address payable public split;

	address public account1 = makeAddr("account1");
	address public account2 = makeAddr("account2");

	function _createSimpleSplit()
		internal
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
		internal
		returns (address[] memory accounts, uint32[] memory amounts)
	{
		accounts = new address[](2);
		accounts[0] = address(new NonReceiver());
		accounts[1] = address(new NonReceiver());

		amounts = new uint32[](2);
		amounts[0] = 5e5;
		amounts[1] = 5e5;
		_createSplit(accounts, amounts);
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
		vm.startPrank(accounts[0]);
		split = payable(splitMainImpl.createSplit(accounts, percents));
		vm.stopPrank();
	}

	function _getSplitConfigHash(
		address _split,
		address[] memory _accounts,
		uint32[] memory _percentAllocations
	) internal view returns (bytes32) {
		bytes32 domainSeparator = _makeSplitDomainHash();
		return
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					domainSeparator,
					_hashSplitFromMemory(_split, _accounts, _percentAllocations)
				)
			);
	}

	function _makeSplitDomainHash() internal view returns (bytes32) {
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
					address(splitMainImpl) // verifying contract
				)
			);
	}

	function _hashSplitFromMemory(
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
