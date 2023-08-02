// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.7.6;
pragma abicoder v2;

import { ISwapRouter } from "v3-periphery/interfaces/ISwapRouter.sol";
import { TransferHelper } from "v3-periphery/libraries/TransferHelper.sol";

import { AggregatorV3Interface } from "chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";
import { IWETH } from "./interfaces/IWETH.sol";

contract SonaSwap {
	uint8 constant USDC_DECIMALS = 6;

	AggregatorV3Interface internal dataFeed;
	ISwapRouter router;
	address USDC;
	IWETH WEth;

	constructor(
		AggregatorV3Interface _dataFeed,
		ISwapRouter _swapRouter,
		address _usdc,
		IWETH _weth
	) {
		dataFeed = _dataFeed;
		router = _swapRouter;
		USDC = _usdc;
		WEth = _weth;
	}

	function getUsdEthPrice() public view returns (uint256 price) {
		// prettier-ignore
		(       /*uint80 roundID*/,
						int signedPrice,
						/*uint startedAt*/,
						/*uint timeStamp*/,
						/*uint80 answeredInRound*/
		) = dataFeed.latestRoundData();

		if (signedPrice < 0) revert("SonaSwap: InvalidPrice");
		// TODO check that timestamp is no more than 1 hour old

		price = uint256(signedPrice) / (10 ** (dataFeed.decimals() - USDC_DECIMALS));
	}

	function swapWEthForUSDC(uint256 _amount) public returns (uint256 amountOut) {
		TransferHelper.safeApprove(address(WEth), address(router), _amount);

		uint256 quote = getQuote(_amount);
		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
			.ExactInputSingleParams({
				tokenIn: address(WEth),
				tokenOut: USDC,
				fee: 500, // 0.5% fee pool
				recipient: msg.sender,
				deadline: block.timestamp,
				amountIn: _amount,
				amountOutMinimum: scaleForSlippage(quote),
				sqrtPriceLimitX96: 0
			});
		amountOut = router.exactInputSingle(params);
	}

	function swapEthForUSDC() public payable returns (uint256 amountOut) {
		WEth.deposit{ value: msg.value }();
		return swapWEthForUSDC(msg.value);
	}

	function getQuote(
		uint256 _amount,
		uint256 _rate
	) public pure returns (uint256 minimumAmount) {
		// allow for 3% slippage
		return ((_rate) * _amount) / 1 ether;
	}

	function getQuote(
		uint256 _amount
	) public view returns (uint256 minimumAmount) {
		return getQuote(_amount, getUsdEthPrice());
	}

	function scaleForSlippage(
		uint256 _amount
	) public pure returns (uint256 scaledAmount) {
		// allow for 3% slippage
		return (_amount * 97) / 100;
	}
}
