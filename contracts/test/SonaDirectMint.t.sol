// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { SonaRewardToken, ISonaRewardToken } from "../SonaRewardToken.sol";
import { SonaDirectMint } from "../SonaDirectMint.sol";
import { ISonaAuthorizer } from "../interfaces/ISonaAuthorizer.sol";
import { AuctionSigner } from "./utils/AuctionSigner.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { Util } from "./Util.sol";
import { VmSafe } from "forge-std/Vm.sol";

abstract contract MinterSigner is
	SonaDirectMint(ISonaRewardToken(address(0)), address(0))
{
	address private constant _VMSAFE_ADDRESS =
		address(uint160(uint256(keccak256("hevm cheat code"))));
	VmSafe internal constant _vmLocal = VmSafe(_VMSAFE_ADDRESS);

	SonaDirectMint public directMint;

	string public mnemonic =
		"test test test test test test test test test test test junk";
	uint256 public authorizerKey = _vmLocal.deriveKey(mnemonic, 0);

	address public authorizer = _vmLocal.addr(authorizerKey);

	function _makeDomainHash() private view returns (bytes32) {
		return
			keccak256(
				abi.encode(
					_EIP712DOMAIN_TYPEHASH,
					keccak256("SonaDirectMint"), // name
					keccak256("1"), // version
					block.chainid, // chain ID
					address(directMint) // verifying contract
				)
			);
	}

	function _hashFromMemory(
		ISonaRewardToken.MetadataBundle memory bundle
	) internal pure returns (bytes32) {
		return
			keccak256(
				abi.encode(
					_METADATABUNDLE_TYPEHASH,
					bundle.tokenId,
					bundle.payout,
					keccak256(bytes(bundle.arweaveTxId))
				)
			);
	}

	function _hashFromMemory(
		MetadataBundles memory _md
	) internal pure returns (bytes32) {
		bytes32[] memory hashedBundles = new bytes32[](_md.bundles.length);

		for (uint i = 0; i < _md.bundles.length; i++) {
			hashedBundles[i] = _hashFromMemory(_md.bundles[i]);
		}
		return
			keccak256(
				abi.encode(
					_METADATABUNDLES_TYPEHASH,
					keccak256(abi.encodePacked(hashedBundles))
				)
			);
	}

	function _getBundlesHash(
		MetadataBundles memory _bundles
	) internal view returns (bytes32) {
		bytes32 domainSeparator = _makeDomainHash();
		return
			keccak256(
				abi.encodePacked("\x19\x01", domainSeparator, _hashFromMemory(_bundles))
			);
	}

	function _signBundles(
		MetadataBundles memory _bundles
	) internal view returns (Signature memory signature) {
		bytes32 bundleHash = _getBundlesHash(_bundles);
		(uint8 v, bytes32 r, bytes32 s) = _vmLocal.sign(authorizerKey, bundleHash);

		return Signature({ v: v, r: r, s: s });
	}
}

contract SonaDirectMintTest is Util, MinterSigner {
	address payable public artistPayout = payable(address(25));
	address public treasuryRecipient = makeAddr("treasuryRecipient");
	// redistribution address getting the fees
	address public redistributionRecipient = makeAddr("redistributionRecipient");
	// reward token recipient
	address public rewardTokenRecipient = makeAddr("rewardTokenRecipient");
	// auction mock
	address public auctionInitializer = makeAddr("auctionInitializer");

	SonaRewardToken public rewardToken;

	function setUp() public {
		SonaRewardToken rewardTokenBase = new SonaRewardToken();
		vm.prank(auctionInitializer);
		ERC1967Proxy proxy = new ERC1967Proxy(
			address(rewardTokenBase),
			abi.encodeWithSelector(
				SonaRewardToken.initialize.selector,
				"SonaRewardToken",
				"SRT",
				address(1),
				address(this)
			)
		);
		rewardToken = SonaRewardToken(address(proxy));
		directMint = new SonaDirectMint(rewardToken, authorizer);

		hoax(address(1));
		rewardToken.grantRole(keccak256("MINTER_ROLE"), address(directMint));
	}

	function test_HashAndSignature() public {
		MetadataBundles memory bundles = _createBundles();

		// ensure our hashing sequence conforms to the standard
		// as implemented by viem in script/signTyped.ts
		bytes32 digest = keccak256(
			abi.encodePacked("\x19\x01", _DOMAIN_SEPARATOR, _hashFromMemory(bundles))
		);

		assertEq(
			digest,
			0xb20accba34cde2c2aa8220486e0131357eaaefec29cca46612fe64c3db9b81ac,
			"Digest Incorrect"
		);
	}

	function test_AuthorizedSignaturesAllowMint() public {
		MetadataBundles memory bundles = _createBundles();
		Signature memory signature = _signBundles(bundles);
		directMint.mint(bundles, signature);
	}

	function test_UnauthorizedSignaturesRevertMint() public {
		MetadataBundles memory bundles = _createBundles();
		Signature memory signature = _signBundles(bundles);
		signature.v = 99;
		vm.expectRevert(SonaAuthorizer_InvalidSignature.selector);
		directMint.mint(bundles, signature);
	}

	function _createBundles()
		private
		view
		returns (MetadataBundles memory bundles)
	{
		ISonaRewardToken.MetadataBundle memory bundle0 = ISonaRewardToken
			.MetadataBundle({
				arweaveTxId: "Hello World!",
				tokenId: 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000044,
				payout: artistPayout
			});
		ISonaRewardToken.MetadataBundle memory bundle1 = ISonaRewardToken
			.MetadataBundle({
				arweaveTxId: "Hello World",
				tokenId: 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000045,
				payout: payable(address(0))
			});

		ISonaRewardToken.MetadataBundle[]
			memory bundleArray = new ISonaRewardToken.MetadataBundle[](2);
		bundleArray[0] = bundle0;
		bundleArray[1] = bundle1;

		bundles = MetadataBundles({ bundles: bundleArray });
	}

	function _createSignedBundles()
		private
		view
		returns (MetadataBundles memory bundles, Signature memory signature)
	{
		signature = Signature(
			28,
			0x82f8cd9d3e37122608a7bbdc411dbb930996862d1cefe7473ec8f93033d7ff41,
			0x644373e39d14f756dd9e2a81e41a1ca6c969951cf34e3972552e106e29f2137a
		);

		bundles = _createBundles();
	}
}
