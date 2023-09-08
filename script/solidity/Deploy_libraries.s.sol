// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import { ZeroCheck } from "../../contracts/utils/ZeroCheck.sol";
import { AddressableTokenId } from "../../contracts/utils/AddressableTokenId.sol";

contract Deployer is Script {
	function run() external {
		string memory mnemonic = vm.envString("MNEMONIC");
		uint256 key = vm.deriveKey(mnemonic, 0);
		address deployer = vm.addr(key);
		console.log("deployer: ", deployer);

		address zeroCheck = getCreate2Address(type(ZeroCheck).creationCode);
		address addressableTokenId = getCreate2Address(
			type(AddressableTokenId).creationCode
		);

		console.log("zeroCheck", zeroCheck);
		console.log("addressableTokenId", addressableTokenId);

		deploy2(type(ZeroCheck).creationCode, "", key);
		deploy2(type(AddressableTokenId).creationCode, "", key);
		console.log("zero check size: ", zeroCheck.code.length);
		console.log("addressableTokenId size: ", addressableTokenId.code.length);
	}

	function getCreate2Address(
		bytes memory creationCode,
		bytes memory args
	) internal view returns (address) {
		bytes32 salt = keccak256(bytes(vm.envString("SONA_DEPLOYMENT_SALT")));
		bytes32 codeHash = hashInitCode(creationCode, args);
		console.log("code hash");
		console.logBytes32(codeHash);
		return computeCreate2Address(salt, codeHash);
	}

	function getCreate2Address(
		bytes memory creationCode
	) internal view returns (address) {
		return getCreate2Address(creationCode, "");
	}

	function deploy2(
		bytes memory deployCode,
		bytes memory args,
		uint256 pk
	) internal {
		bytes32 salt = keccak256(bytes(vm.envString("SONA_DEPLOYMENT_SALT")));
		console.log("salt");
		console.logBytes32(salt);
		bytes memory payload = abi.encodePacked(salt, deployCode, args);
		vm.broadcast(pk);
		(bool success, ) = CREATE2_FACTORY.call(payload);
		if (!success) revert("create2 failed");
		/*
		(deployedTo) = abi.decode(returnData, (address));
		console.log("deployed to address: ", deployedTo);
		*/
	}
}
