// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { ISplitMain } from "../../payout/interfaces/ISplitMain.sol";
import { ISonaAuthorizer } from "../../interfaces/ISonaAuthorizer.sol";
import { SplitMain } from "../../payout/SplitMain.sol";
import { SplitWallet } from "../../payout/SplitWallet.sol";
import { Util } from "../Util.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SplitHelpers } from "../util/SplitHelpers.t.sol";
import { MockERC20 } from "../../../lib/solady/test/utils/mocks/MockERC20.sol";

contract SonaTestSplits is Util, ISonaAuthorizer, SplitHelpers {
	MockERC20 public mockERC20 = new MockERC20("Mock Token", "USDC", 6);

	event UpdateSplit(address indexed split);

	function setUp() public {
		splitMainImpl = new SplitMain(authorizer);
	}

	function test_UpdateSplit() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		Signature memory sig = _signSplitConfig(split, accounts, amounts);

		// Only a controller can update a Split
		vm.expectEmit(true, false, false, false, address(splitMainImpl));
		emit UpdateSplit(address(split));
		hoax(accounts[0]);
		splitMainImpl.updateSplit(split, accounts, amounts, sig);

		vm.expectRevert(
			abi.encodeWithSelector(SplitMain.Unauthorized.selector, accounts[1])
		);
		hoax(accounts[1]);
		splitMainImpl.updateSplit(split, accounts, amounts, sig);
	}

	function test_revertUpdateSplitUnauthorized() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		Signature memory sig = _signSplitConfig(split, accounts, amounts);

		vm.expectRevert(
			abi.encodeWithSelector(SplitMain.Unauthorized.selector, address(3))
		);
		hoax(address(3));
		splitMainImpl.updateSplit(split, accounts, amounts, sig);
	}

	function test_distributeERC20ToEOA() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		hoax(address(0));
		mockERC20.mint(split, 1e8);

		uint initialBalance2 = mockERC20.balanceOf(account2);
		uint initialBalance1 = mockERC20.balanceOf(account1);

		splitMainImpl.distributeERC20(
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

		splitMainImpl.distributeERC20(
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

		splitMainImpl.distributeETH(split, accounts, amounts);

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

		splitMainImpl.distributeETH(split, accounts, amounts);

		uint finalBalance2 = accounts[0].balance;
		uint finalBalance1 = accounts[1].balance;
		assertEq(finalBalance2 - initialBalance2, 0);
		assertEq(finalBalance1 - initialBalance1, 0);
	}

	// TODO add check to ensure invalid signatures revert
}
