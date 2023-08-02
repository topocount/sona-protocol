// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.7.6;
pragma abicoder v2;

import { SonaSwap, IWETH, ISwapRouter, AggregatorV3Interface } from "../SonaSwap.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import "forge-std/console.sol";

contract SonaSwapTest is Test {
	uint256 mainnetFork;
	string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

	AggregatorV3Interface public constant dataFeed =
		AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
	IWETH public constant WETH9 =
		IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
	ISwapRouter public constant router =
		ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
	address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
	address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

	SonaSwap public swap;

	function setUp() public {
		mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 17828120);
		swap = new SonaSwap(dataFeed, router, USDC, WETH9);
	}

	// TODO fuzz test this with different block numbers
	function test_ForkedIntegrationCanSwap() public {
		uint256 amount = 0.25 ether;
		uint256 expectedPrice = swap.getQuote(amount);
		uint256 amt = swap.swapEthForUSDC{value: amount}();
		assertApproxEqRelDecimal(amt, expectedPrice, 5e15, 6); // 0.5% = 5e15
		uint256 balance = IERC20(USDC).balanceOf(address(this));
		assertEq(balance, amt, "balance not equal to expected amount");
	}

	function test_ForkedIntegrationCanSwapZeroReverts() public {
		uint256 amount = 0 ether;
		vm.expectRevert();
		swap.swapEthForUSDC{value: amount}();
	}
}
