// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.7.6;
pragma abicoder v2;

import { ISwapRouter } from "v3-periphery/interfaces/ISwapRouter.sol";
import { TransferHelper } from "v3-periphery/libraries/TransferHelper.sol";

import { AggregatorV3Interface } from "chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { ISonaSwap } from "lib/common/ISonaSwap.sol";

contract SonaSwap is ISonaSwap {
	uint8 constant USDC_DECIMALS = 6;

	AggregatorV3Interface public dataFeed;
	ISwapRouter public router;
	address public USDC;
	IWETH public WEth;

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
		_weth.approve(address(_swapRouter), type(uint256).max);
	}

	function getUsdEthPrice() public view override returns (uint256 price) {
		// prettier-ignore
		(       /*uint80 roundID*/,
						int signedPrice,
						/*uint startedAt*/,
						uint priceTimestamp,
						/*uint80 answeredInRound*/
		) = dataFeed.latestRoundData();

		if (signedPrice < 0) revert("SonaSwap: InvalidPrice");
		if (block.timestamp - priceTimestamp > 1 hours)
			revert("SonaSwap: Chainlink Heartbeat");

		price =
			scaleForSlippage(uint256(signedPrice)) /
			(10 ** (dataFeed.decimals() - USDC_DECIMALS));
	}

	function swapWEthForUSDC(
		uint256 _amount
	) external override returns (uint256 amountOut) {
		TransferHelper.safeTransferFrom(
			address(WEth),
			msg.sender,
			address(this),
			_amount
		);
		return _swapWEthForUSDC(_amount);
	}

	function _swapWEthForUSDC(
		uint256 _amount
	) internal returns (uint256 amountOut) {

		uint256 quote = getQuote(_amount);
		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
			.ExactInputSingleParams({
				tokenIn: address(WEth),
				tokenOut: USDC,
				fee: 500, // 0.05% fee pool
				recipient: msg.sender,
				deadline: block.timestamp,
				amountIn: _amount,
				amountOutMinimum: quote,
				sqrtPriceLimitX96: 0
			});
		amountOut = router.exactInputSingle(params);
	}

	function swapEthForUSDC()
		public
		payable
		override
		returns (uint256 amountOut)
	{
		WEth.deposit{ value: msg.value }();
		return _swapWEthForUSDC(msg.value);
	}

	function getQuote(
		uint256 _amount,
		uint256 _rate
	) public pure override returns (uint256 minimumAmount) {
		return ((_rate) * _amount) / 1 ether;
	}

	function getQuote(
		uint256 _amount
	) public view override returns (uint256 minimumAmount) {
		return getQuote(_amount, getUsdEthPrice());
	}

	function scaleForSlippage(
		uint256 _amount
	) public pure returns (uint256 scaledAmount) {
		// allow for 0.5% slippage
		return (_amount * 995) / 1000;
	}
}
