// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import { SonaRewards } from "../../contracts/SonaRewards.sol";
import { SonaDirectMint } from "../../contracts/SonaDirectMint.sol";
import { SonaRewardToken } from "../../contracts/SonaRewardToken.sol";
import { SonaReserveAuction } from "../../contracts/SonaReserveAuction.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IWETH } from "../../contracts/interfaces/IWETH.sol";
import { Weth9Mock } from "../../contracts/test/mock/Weth9Mock.sol";
import { ISonaSwap } from "../../lib/common/ISonaSwap.sol";
import { SplitMain } from "../../contracts/payout/SplitMain.sol";
import { SonaDirectMint } from "../../contracts/SonaDirectMint.sol";

contract Deployer is Script {
	function run() external {
		string memory mnemonic = vm.envString("MNEMONIC");
		(address deployer, uint256 pk) = deriveRememberKey(mnemonic, 0);

		address rewardToken = deployRewardToken(mnemonic);

		// Deploy Mocks for PoC Tests
		// TODO: convert create non-mock address cases for mainnet
		vm.startBroadcast(pk);
		IERC20 mockToken = IERC20(address(new ERC20Mock()));
		Weth9Mock mockWeth = new Weth9Mock();
		vm.stopBroadcast();

		SplitMain splits = deploySplitMain(mnemonic, mockWeth, mockToken);

		address directMint = deployDirectMint(mnemonic, rewardToken);

		address reserveAuction = deployReserveAuction(
			mnemonic,
			rewardToken,
			splits,
			address(mockWeth)
		);

		deployRewards(mnemonic, rewardToken, address(mockToken), "", splits);

		address _SONA_OWNER = vm.addr(vm.deriveKey(mnemonic, 1));
		bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
		bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");

		console.log("reward token: ", rewardToken);
		console.log("direct mint: ", directMint);
		console.log("reserve auction: ", reserveAuction);
		vm.startBroadcast(pk);
		SonaRewardToken(rewardToken).grantRole(MINTER_ROLE, directMint);
		SonaRewardToken(rewardToken).grantRole(MINTER_ROLE, reserveAuction);
		SonaRewardToken(rewardToken).grantRole(ADMIN_ROLE, _SONA_OWNER);
		SonaRewardToken(rewardToken).renounceRole(ADMIN_ROLE, deployer);
		vm.stopBroadcast();
	}

	function deploySplitMain(
		string memory mnemonic,
		IWETH weth,
		IERC20 usdc
	) internal returns (SplitMain splits) {
		ISonaSwap swap = ISonaSwap(vm.envAddress("SONA_SWAP"));
		uint256 pk = vm.deriveKey(mnemonic, 0);
		vm.broadcast(pk);
		return new SplitMain(weth, usdc, swap);
	}

	function deployRewards(
		string memory mnemonic,
		address rewardToken,
		address payoutToken,
		string memory claimUrl,
		SplitMain splitMain
	) internal {
		uint256 pk = vm.deriveKey(mnemonic, 0);
		vm.broadcast(pk);
		SonaRewards rewardsBase = new SonaRewards();

		address _SONA_OWNER = vm.addr(vm.deriveKey(mnemonic, 1));
		address _REDISTRIBUTION_RECIPIENT = vm.addr(vm.deriveKey(mnemonic, 3));

		vm.broadcast(pk);
		new ERC1967Proxy(
			address(rewardsBase),
			abi.encodeWithSelector(
				SonaRewards.initialize.selector,
				_SONA_OWNER,
				address(rewardToken),
				payoutToken,
				address(0),
				_REDISTRIBUTION_RECIPIENT, //todo: holder of protocol fees(?)
				claimUrl,
				splitMain
			)
		);
	}

	function deployRewardToken(
		string memory mnemonic
	) internal returns (address rewardTokenAddress) {
		bytes memory initCode = type(SonaRewardToken).creationCode;
		address tokenBase = getCreate2Address(initCode, "");
		console.log("token base: ", tokenBase);

		deploy2(initCode, "", vm.deriveKey(mnemonic, 0));
		if (tokenBase.code.length == 0) revert("token base Deployment failed");

		address _TEMP_SONA_OWNER = vm.addr(vm.deriveKey(mnemonic, 0));
		bytes memory rewardTokenInitializerArgs = abi.encodeWithSelector(
			SonaRewardToken.initialize.selector,
			"Sona Rewards Token",
			"SONA",
			_TEMP_SONA_OWNER
		);

		initCode = type(ERC1967Proxy).creationCode;
		rewardTokenAddress = getCreate2Address(
			initCode,
			abi.encode(tokenBase, rewardTokenInitializerArgs)
		);

		deploy2(
			initCode,
			abi.encode(tokenBase, rewardTokenInitializerArgs),
			vm.deriveKey(mnemonic, 0)
		);
		if (rewardTokenAddress.code.length == 0)
			revert("reward token Deployment failed");
	}

	function deployDirectMint(
		string memory mnemonic,
		address rewardToken
	) internal returns (address directMintAddress) {
		address _AUTHORIZER = vm.addr(vm.deriveKey(mnemonic, 2));

		uint256 pk = vm.deriveKey(mnemonic, 0);
		vm.broadcast(pk);
		SonaDirectMint directMint = new SonaDirectMint(
			SonaRewardToken(rewardToken),
			_AUTHORIZER
		);

		return address(directMint);
	}

	function deployReserveAuction(
		string memory mnemonic,
		address rewardToken,
		SplitMain splits,
		address weth
	) internal returns (address reserveAuctionAddress) {
		address _AUTHORIZER = vm.addr(vm.deriveKey(mnemonic, 2));
		address _TREASURY_RECIPIENT = vm.addr(vm.deriveKey(mnemonic, 3));
		address _REDISTRIBUTION_RECIPIENT = vm.addr(vm.deriveKey(mnemonic, 3));

		uint256 pk = vm.deriveKey(mnemonic, 0);
		vm.broadcast(pk);
		SonaReserveAuction auctionBase = new SonaReserveAuction();

		address _SONA_OWNER = vm.addr(vm.deriveKey(mnemonic, 1));

		bytes memory reserveAuctionInitializerArgs = abi.encodeWithSelector(
			SonaReserveAuction.initialize.selector,
			_TREASURY_RECIPIENT,
			_REDISTRIBUTION_RECIPIENT,
			_AUTHORIZER,
			SonaRewardToken(rewardToken),
			splits,
			_SONA_OWNER,
			weth
		);

		vm.startBroadcast(pk);
		reserveAuctionAddress = address(
			new ERC1967Proxy(address(auctionBase), reserveAuctionInitializerArgs)
		);
		vm.stopBroadcast();
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

contract ERC20Mock is ERC20 {
	constructor() ERC20("USD Coin", "USDC") {}

	function mint(address account, uint256 amount) external {
		_mint(account, amount);
	}

	function burn(address account, uint256 amount) external {
		_burn(account, amount);
	}
}
