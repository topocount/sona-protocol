// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { ISplitMain } from "../../payout/interfaces/ISplitMain.sol";
import { SplitMain } from "../../payout/SplitMain.sol";
import { SplitWallet } from "../../payout/SplitWallet.sol";
import { Util } from "../Util.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SplitHelpers } from "../util/SplitHelpers.t.sol";
import { MockERC20 } from "../../../lib/solady/test/utils/mocks/MockERC20.sol";
import { Weth9Mock, IWETH } from "../mock/Weth9Mock.sol";
import { ISonaSwap } from "lib/common/ISonaSwap.sol";

contract SonaTestSplits is SplitHelpers {
	MockERC20 public mockERC20 = new MockERC20("Mock Token", "USDC", 6);
	Weth9Mock public mockWeth = new Weth9Mock();

	address public swapAddr;

	uint256 mainnetFork;
	string MAINNET_RPC_URL = vm.envString("MAINNET_FORK_RPC_URL");

	address public constant dataFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
	IWETH public constant WETH9 =
		IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
	address public constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
	address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

	event UpdateSplit(address indexed split);

	function setUp() public {
		swapAddr = deployCode(
			"SonaSwap.sol",
			abi.encode(dataFeed, router, USDC, WETH9)
		);
		splitMainImpl = new SplitMain(
			mockWeth,
			IERC20(address(mockERC20)),
			ISonaSwap(swapAddr)
		);
	}

	function test_UpdateSplit() public {
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();

		// Only a controller can update a Split
		vm.expectEmit(true, false, false, false, address(splitMainImpl));
		emit UpdateSplit(address(split));
		hoax(accounts[0]);
		splitMainImpl.updateSplit(split, accounts, amounts);

		vm.expectRevert(
			abi.encodeWithSelector(SplitMain.Unauthorized.selector, accounts[1])
		);
		hoax(accounts[1]);
		splitMainImpl.updateSplit(split, accounts, amounts);
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

	function test_distrbuteNonUSDCToController() public {
		uint256 amount = 1e20;
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		hoax(address(0));

		address controller = splitMainImpl.getController(split);

		MockERC20 notUSDC = new MockERC20("Mock Tether Token", "USDT", 18);
		notUSDC.mint(split, amount);

		uint initialBalance2 = notUSDC.balanceOf(account2);
		uint initialBalance1 = notUSDC.balanceOf(account1);

		splitMainImpl.distributeERC20(
			split,
			IERC20(address(notUSDC)),
			accounts,
			amounts
		);

		uint finalBalance2 = notUSDC.balanceOf(account2);
		uint finalBalance1 = notUSDC.balanceOf(account1);

		assertEq(finalBalance2 - initialBalance2, 0);
		assertEq(finalBalance1 - initialBalance1, 0);
		assertEq(
			splitMainImpl.getERC20Balance(
				splitMainImpl.getController(split),
				IERC20(address(notUSDC))
			),
			amount
		);

		IERC20[] memory tokens = new IERC20[](1);
		tokens[0] = IERC20(address(notUSDC));
		splitMainImpl.withdraw(controller, 0, tokens);

		uint finalBalanceController = notUSDC.balanceOf(controller);

		assertEq(finalBalanceController, amount - 1);
	}

	function test_SwapETHAndDistributeUSDC() public {
		uint256 amount = 10 ether;
		mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 17828120);
		swapAddr = deployCode(
			"SonaSwap.sol",
			abi.encode(dataFeed, router, USDC, WETH9)
		);
		splitMainImpl = new SplitMain(WETH9, IERC20(USDC), ISonaSwap(swapAddr));
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		hoax(address(0));
		payable(split).transfer(amount);

		uint initialBalance2 = IERC20(USDC).balanceOf(accounts[0]);
		uint initialBalance1 = IERC20(USDC).balanceOf(accounts[1]);

		uint256 expectedPrice = ISonaSwap(swapAddr).getQuote(amount);
		splitMainImpl.distributeETH(split, accounts, amounts);

		uint finalBalance2 = IERC20(USDC).balanceOf(accounts[0]);
		uint finalBalance1 = IERC20(USDC).balanceOf(accounts[1]);
		uint dist2 = (finalBalance2 - initialBalance2);
		uint dist1 = (finalBalance1 - initialBalance1);
		assertApproxEqRelDecimal(dist2, expectedPrice / 2, 5e15, 6); // 0.5% = 5e15
		assertApproxEqRelDecimal(dist1, expectedPrice / 2, 5e15, 6); // 0.5% = 5e15
		assertEq(dist1, dist2, "unequal distribution");
	}

	function test_distributeWETHAndETHToEOA() public {
		uint256 ETHAmount = 5 ether;
		uint256 WETHAmount = 5 ether;
		uint256 amount = ETHAmount + WETHAmount;
		mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 17828120);
		swapAddr = deployCode(
			"SonaSwap.sol",
			abi.encode(dataFeed, router, USDC, WETH9)
		);
		splitMainImpl = new SplitMain(WETH9, IERC20(USDC), ISonaSwap(swapAddr));
		(address[] memory accounts, uint32[] memory amounts) = _createSimpleSplit();
		hoax(address(0));
		WETH9.deposit{ value: WETHAmount }();
		hoax(address(0));
		WETH9.transfer(address(split), WETHAmount);
		hoax(address(0));
		payable(split).transfer(ETHAmount);

		uint initialBalance2 = IERC20(USDC).balanceOf(accounts[0]);
		uint initialBalance1 = IERC20(USDC).balanceOf(accounts[1]);

		uint256 expectedPrice = ISonaSwap(swapAddr).getQuote(amount);
		splitMainImpl.distributeETH(split, accounts, amounts);

		uint finalBalance2 = IERC20(USDC).balanceOf(accounts[0]);
		uint finalBalance1 = IERC20(USDC).balanceOf(accounts[1]);
		uint dist2 = (finalBalance2 - initialBalance2);
		uint dist1 = (finalBalance1 - initialBalance1);
		assertApproxEqRelDecimal(dist2, expectedPrice / 2, 5e15, 6); // 0.5% = 5e15
		assertApproxEqRelDecimal(dist1, expectedPrice / 2, 5e15, 6); // 0.5% = 5e15
		assertEq(dist1, dist2, "unequal distribution");
	}
}
