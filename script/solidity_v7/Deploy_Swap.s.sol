// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.6;

import "forge-std/Script.sol";
import { SonaSwap, IWETH } from "../../contracts_swap/SonaSwap.sol";

contract DeploySwap is Script {
	address public constant dataFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
	IWETH public constant WETH9 =
		IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
	address public constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
	address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

	function run() external {
		string memory mnemonic = vm.envString("MNEMONIC");
		(address deployer, uint256 pk) = deriveRememberKey(mnemonic, 0);
		console.log("deployer address: ", deployer);
		address swap = deploySwap(pk);
		console.log("swap address: ", swap);
	}

	function deploySwap(uint256 pk) private returns (address swap) {
		bytes memory initCode = type(SonaSwap).creationCode;
		bytes memory swapArgs = abi.encode(dataFeed, router, USDC, WETH9);
		swap = getCreate2Address(initCode, swapArgs);
		deploy2(initCode, swapArgs, pk);
	}

	function getCreate2Address(
		bytes memory creationCode,
		bytes memory args
	) internal view returns (address) {
		bytes32 salt = keccak256(bytes(vm.envString("SONA_DEPLOYMENT_SALT")));
		bytes32 codeHash = hashInitCode(creationCode, args);
		return computeCreate2Address(salt, codeHash);
	}

	function deploy2(
		bytes memory deployCode,
		bytes memory args,
		uint256 pk
	) internal {
		bytes32 salt = keccak256(bytes(vm.envString("SONA_DEPLOYMENT_SALT")));
		bytes memory payload = abi.encodePacked(salt, deployCode, args);
		vm.broadcast(pk);
		(bool success, ) = CREATE2_FACTORY.call(payload);
		if (!success) revert("create2 failed");
	}
}
