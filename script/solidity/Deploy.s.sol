// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import { SonaRewards } from "../../contracts/SonaRewards.sol";
import { SonaRewardToken } from "../../contracts/SonaRewardToken.sol";
import { SonaReserveAuction } from "../../contracts/SonaReserveAuction.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IWETH } from "../../contracts/interfaces/IWETH.sol";
import { Weth9Mock } from "../../contracts/test/mock/Weth9Mock.sol";

contract Deployer is Script {
	function setUp() public {}

	function run() external {
		string memory mnemonic = vm.envString("MNEMONIC");
		uint256 key = vm.deriveKey(mnemonic, 0);
		address _SONA_OWNER = vm.addr(vm.deriveKey(mnemonic, 1));
		address _AUTHORIZER = vm.addr(vm.deriveKey(mnemonic, 2));
		address _TREASURY_RECIPIENT = vm.addr(vm.deriveKey(mnemonic, 3));
		address _REDISTRIBUTION_RECIPIENT = vm.addr(vm.deriveKey(mnemonic, 3));

		console.log("deployer: ", vm.addr(key));

		vm.startBroadcast(key);

		// Deploy Mocks for PoC Tests
		ERC20Mock mockToken = new ERC20Mock();
		Weth9Mock mockWeth = new Weth9Mock();

		// Deploy Reward NFT contract

		// Deploy TrackAuction
		SonaReserveAuction auctionBase = new SonaReserveAuction();
		SonaRewardToken rewardTokenBase = new SonaRewardToken();
		ERC1967Proxy proxy = new ERC1967Proxy(
			address(auctionBase),
			abi.encodeWithSelector(
				SonaReserveAuction.initialize.selector,
				_TREASURY_RECIPIENT,
				_REDISTRIBUTION_RECIPIENT,
				_AUTHORIZER,
				rewardTokenBase,
				address(0), // TODO deploy splitMain impl
				_SONA_OWNER,
				mockWeth
			)
		);
		SonaReserveAuction auction = SonaReserveAuction(address(proxy));

		console.log("mock WETH address: ", address(mockWeth));
		console.log("mock ERC20 address: ", address(mockToken));
		console.log("Reward NFT Address: ", address(auction.rewardToken()));
		console.log("Auction Address: ", address(auction));

		SonaRewards rewardsBase = new SonaRewards();
		ERC1967Proxy rewards = new ERC1967Proxy(
			address(rewardsBase),
			abi.encodeWithSelector(
				SonaRewards.initialize.selector,
				_SONA_OWNER,
				address(auction.rewardToken()),
				address(mockToken),
				address(0),
				_REDISTRIBUTION_RECIPIENT, //todo: holder of protocol fees(?)
				"" //todo: claimLookupUrl
			)
		);

		console.log("Reward Claims address: ", address(rewards));

		vm.stopBroadcast();
	}
}

contract ERC20Mock is ERC20 {
	constructor() ERC20("USD Coin", "USDC") {}

	function mint(address account, uint256 amount) external {
		_mint(account, amount);
	}

	function burn(address account, uint256 amount) external {
		_burn(account, amount);
	}
}
