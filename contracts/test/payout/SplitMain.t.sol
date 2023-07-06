// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { ISplitMain } from "../../payout/interfaces/ISplitMain.sol";
import { SplitMain } from "../../payout/SplitMain.sol";
import { SplitWallet } from "../../payout/SplitWallet.sol";
import { Util } from "../Util.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

//import "forge-std/console.sol";

contract SonaTestSplits is Util, SplitMain {
	SplitMain public splitMain;
	address public split;

	function setUp() public {
		splitMain = new SplitMain();
	}

	function test_UpdateSplit() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();

		vm.expectEmit(true, false, false, false, address(splitMain));
		emit UpdateSplit(address(split));
		hoax(address(1));
		splitMain.updateSplit(split, accounts, amounts);
	}

	function test_revertUpdateSplitUnauthorized() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();

		vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(3)));
		hoax(address(3));
		splitMain.updateSplit(split, accounts, amounts);
	}

	function test_distributeETH() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		hoax(address(0));
		payable(split).transfer(10 ether);

		splitMain.distributeETH(split, accounts, amounts);

		ERC20[] memory emptyERC20s = new ERC20[](0);

		uint initialBalance = address(1).balance;
		splitMain.withdraw(address(1), 1, emptyERC20s);
		splitMain.withdraw(address(2), 1, emptyERC20s);
		uint finalBalance = address(1).balance;
		assertEq(finalBalance - initialBalance, 4999999999999999999);
	}

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
}
