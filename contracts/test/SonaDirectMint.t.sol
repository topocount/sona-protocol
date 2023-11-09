// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { SonaRewardToken, ISonaRewardToken } from "../SonaRewardToken.sol";
import { SonaDirectMint } from "../SonaDirectMint.sol";
import { SonaTokenAuthorizor } from "../SonaTokenAuthorizor.sol";
import { MinterSigner } from "./util/MinterSigner.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { Util } from "./Util.sol";
import { VmSafe } from "forge-std/Vm.sol";

contract SonaDirectMintTest is
	Util,
	SonaDirectMint(ISonaRewardToken(address(0)), address(0)),
	MinterSigner
{
	address payable public artistPayout = payable(address(25));
	address public treasuryRecipient = makeAddr("treasuryRecipient");
	// redistribution address getting the fees
	address public redistributionRecipient = makeAddr("redistributionRecipient");
	// reward token recipient
	address public rewardTokenRecipient = makeAddr("rewardTokenRecipient");
	// auction mock
	address public auctionInitializer = makeAddr("auctionInitializer");

	SonaRewardToken public rewardToken;
	SonaDirectMint public directMint;

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

		_makeDomainHash("SonaDirectMint", address(directMint));

		hoax(address(1));
		rewardToken.grantRole(keccak256("MINTER_ROLE"), address(directMint));
	}

	function test_HashAndSignature() public {
		ISonaRewardToken.TokenMetadata[] memory bundles = _createBundles();

		// ensure our hashing sequence conforms to the standard
		// as implemented by viem in script/signTyped.ts
		bytes32 digest = keccak256(
			abi.encodePacked("\x19\x01", _DOMAIN_SEPARATOR, _hashFromMemory(bundles))
		);

		assertEq(
			digest,
			0xf15fbb19967880136d947923bfdbf5b9d629c662a171bb36d18d0a8b65949106,
			"Digest Incorrect"
		);
	}

	function test_AuthorizedSignaturesAllowMint() public {
		ISonaRewardToken.TokenMetadata[] memory bundles = _createBundles();
		Signature memory signature = _signBundles(bundles);
		directMint.mint(bundles, signature);
	}

	function test_UnauthorizedSignaturesRevertMint() public {
		ISonaRewardToken.TokenMetadata[] memory bundles = _createBundles();
		Signature memory signature = _signBundles(bundles);
		signature.v = 99;
		vm.expectRevert(SonaAuthorizor_InvalidSignature.selector);
		directMint.mint(bundles, signature);
	}

	function _createBundles()
		private
		view
		returns (ISonaRewardToken.TokenMetadata[] memory bundles)
	{
		ISonaRewardToken.TokenMetadata memory bundle0 = ISonaRewardToken
			.TokenMetadata({
				arweaveTxId: "Hello World!",
				tokenId: 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000044,
				payout: artistPayout
			});
		ISonaRewardToken.TokenMetadata memory bundle1 = ISonaRewardToken
			.TokenMetadata({
				arweaveTxId: "Hello World",
				tokenId: 0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f000000000000000000000045,
				payout: payable(address(0))
			});

		ISonaRewardToken.TokenMetadata[]
			memory bundleArray = new ISonaRewardToken.TokenMetadata[](2);
		bundleArray[0] = bundle0;
		bundleArray[1] = bundle1;

		bundles = bundleArray;
	}

	function _createSignedBundles()
		private
		view
		returns (
			ISonaRewardToken.TokenMetadata[] memory metadatas,
			Signature memory signature
		)
	{
		signature = Signature(
			27,
			0x43ac7cd7fd5970c3926addaac069cc20764ec1461b786bdb87184109fc481ae4,
			0x269e17a9d13bfd1a68af563aa3b732cd1776bcd0dbc2904d0f3a3829d24caf95
		);

		metadatas = _createBundles();
	}
}
