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

contract UpgradeAuction is Script {
	function setUp() public {}

	function run() external {
		string memory mnemonic = vm.envString("MNEMONIC");
		SonaReserveAuction auctionProxy = SonaReserveAuction(
			vm.envAddress("AUCTION_ADDR")
		);
		uint256 key = vm.deriveKey(mnemonic, 1);

		console.log("deployer: ", vm.addr(key));

		vm.startBroadcast(key);

		// Deploy TrackAuction
		SonaReserveAuction auctionBase = new SonaReserveAuction();

		auctionProxy.upgradeTo(address(auctionBase));
	}
}

contract UpgradeRewardToken is Script {
	function setUp() public {}

	function run() external {
		string memory mnemonic = vm.envString("MNEMONIC");
		SonaRewardToken tokenProxy = SonaRewardToken(
			vm.envAddress("REWARD_TOKEN_ADDR")
		);
		uint256 key = vm.deriveKey(mnemonic, 1);

		console.log("deployer: ", vm.addr(key));

		vm.startBroadcast(key);

		// Deploy Reward Token
		SonaRewardToken tokenBase = new SonaRewardToken();

		tokenProxy.upgradeTo(address(tokenBase));
	}
}

contract UpgradeRewards is Script {
	function setUp() public {}

	function run() external {
		string memory mnemonic = vm.envString("MNEMONIC");
		SonaRewards rewardsProxy = SonaRewards(
			payable(vm.envAddress("REWARDS_ADDR"))
		);
		uint256 key = vm.deriveKey(mnemonic, 1);

		console.log("deployer: ", vm.addr(key));

		vm.startBroadcast(key);

		// Deploy Reward Token
		SonaRewards rewardsBase = new SonaRewards();

		rewardsProxy.upgradeTo(address(rewardsBase));
	}
}
