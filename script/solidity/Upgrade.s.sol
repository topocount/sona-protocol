// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import { ISplitMain } from "../../contracts/payout/SplitMain.sol";
import { SonaDirectMint } from "../../contracts/SonaDirectMint.sol";
import { IWETH } from "../../contracts/interfaces/IWETH.sol";
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
		SonaReserveAuction auctionBase = new SonaReserveAuction(1 days);

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

contract MigrateRewardToken is Script {
	address[] internal _OWNER;
	address internal _REDISTRIBUTION;
	address internal _TREASURY;
	address internal _AUTHORIZER;
	string internal _URI_DOMAIN;

	function run() external {
		string memory mnemonic = vm.envString("MNEMONIC");
		address tokenBase = vm.envAddress("REWARD_TOKEN_BASE_ADDR");
		uint256 key = vm.deriveKey(mnemonic, 0);

		_TREASURY = vm.envAddress("SONA_TREASURY_ADDRESS");
		_REDISTRIBUTION = vm.envAddress("SONA_REDISTRIBUTION_ADDRESS");
		address _TEMP_SONA_OWNER = vm.addr(key);
		_URI_DOMAIN = vm.envString("SONA_TOKEN_URI_DOMAIN");
		_AUTHORIZER = vm.envAddress("SONA_AUTHORIZER_ADDRESS");
		_OWNER = vm.envAddress("SONA_OWNER_ADDRESS", ",");

		console.log("deployer: ", vm.addr(key));

		bytes memory rewardTokenInitializerArgs = abi.encodeWithSelector(
			SonaRewardToken.initialize.selector,
			"Sona Rewards Token",
			"SONA",
			_TEMP_SONA_OWNER,
			_TREASURY,
			_URI_DOMAIN
		);

		vm.startBroadcast(key);
		address rewardToken = address(
			new ERC1967Proxy(address(tokenBase), rewardTokenInitializerArgs)
		);

		SonaDirectMint directMint = new SonaDirectMint(
			SonaRewardToken(rewardToken),
			_AUTHORIZER
		);
		vm.stopBroadcast();

		bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
		bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");

		vm.startBroadcast(key);
		SonaRewardToken(rewardToken).grantRole(MINTER_ROLE, address(directMint));
		SonaRewardToken(rewardToken).grantRole(
			MINTER_ROLE,
			0xF8F61D6aF83098A490F503AaD96F0095f816DEd8
		);
		vm.stopBroadcast();

		for (uint i = 0; i < _OWNER.length; i++) {
			vm.startBroadcast(key);
			SonaRewardToken(rewardToken).grantRole(ADMIN_ROLE, _OWNER[i]);
			vm.stopBroadcast();
		}

		vm.startBroadcast(key);
		SonaRewardToken(rewardToken).renounceRole(ADMIN_ROLE, vm.addr(key));
		vm.stopBroadcast();

		console.log("direct mint: ", address(directMint));
		console.log("reward token: ", rewardToken);
	}

	function migrateAuction() public {
		_TREASURY = vm.envAddress("SONA_TREASURY_ADDRESS");
		_REDISTRIBUTION = vm.envAddress("SONA_REDISTRIBUTION_ADDRESS");
		_AUTHORIZER = vm.envAddress("SONA_AUTHORIZER_ADDRESS");
		address _REWARD_TOKEN = vm.envAddress("SONA_REWARD_TOKEN");

		vm.startBroadcast();
		SonaReserveAuction auction = SonaReserveAuction(
			0xF8F61D6aF83098A490F503AaD96F0095f816DEd8
		);
		auction.setConfig(
			_TREASURY,
			_REDISTRIBUTION,
			_AUTHORIZER,
			SonaRewardToken(_REWARD_TOKEN),
			ISplitMain(0x6A6553e4d4732Cbb10e33069480A8f24Ad678CCE), // split main
			IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
		);
	}
}
