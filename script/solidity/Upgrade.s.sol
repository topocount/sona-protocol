
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
		SonaReserveAuction auctionProxy = SonaReserveAuction(vm.envAddress("AUCTION"));
		uint256 key = vm.deriveKey(mnemonic, 1);
		address _SONA_OWNER = vm.addr(vm.deriveKey(mnemonic, 1));
		address _AUTHORIZER = vm.addr(vm.deriveKey(mnemonic, 2));
		address _TREASURY_RECIPIENT = vm.addr(vm.deriveKey(mnemonic, 3));
		address _REDISTRIBUTION_RECIPIENT = vm.addr(vm.deriveKey(mnemonic, 3));

		console.log("deployer: ", vm.addr(key));

		vm.startBroadcast(key);

		// Deploy TrackAuction
		SonaReserveAuction auctionBase = new SonaReserveAuction();

		auctionProxy.upgradeTo(address(auctionBase));

	}
}
