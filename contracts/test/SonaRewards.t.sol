// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC721Upgradeable as IERC721 } from "openzeppelin-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { Merkle } from "murky/Merkle.sol";

import { SplitMain, ISplitMain } from "../payout/SplitMain.sol";
import { SonaRewards } from "../SonaRewards.sol";
import { IRewardGateway } from "../interfaces/IRewardGateway.sol";
import { Util } from "./Util.sol";
import { SonaRewardToken } from "../SonaRewardToken.sol";
import { RewardTokenMock as MockRewardToken } from "./mock/RewardTokenMock.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { MockERC20 } from "../../lib/solady/test/utils/mocks/MockERC20.sol";
import { Weth9Mock, IWETH } from "./mock/Weth9Mock.sol";
import { ERC20ReturnTrueMock, ERC20NoReturnMock, ERC20ReturnFalseMock } from "./mock/ERC20Mock.sol";
import { SplitHelpers } from "./util/SplitHelpers.t.sol";
import { ISonaSwap } from "lib/common/ISonaSwap.sol";

/* solhint-disable max-states-count */
contract SonaTestRewards is Util, SonaRewards, SplitHelpers {
	event Transfer(address indexed from, address indexed to, uint256 value);

	SonaRewards public rewardsBase;
	SonaRewards public rewards;
	ERC1967Proxy public proxy;
	SonaRewards public wEthRewardsBase;
	SonaRewards public wEthRewards;
	ERC1967Proxy public wEthProxy;
	address public rewardAdmin = makeAddr("rewardAdmin");
	address public rewardHolder = makeAddr("rewardHolder");

	Merkle public m = new Merkle();
	ERC20ReturnTrueMock public mockRewardToken = new ERC20ReturnTrueMock();
	Weth9Mock public mockWeth = new Weth9Mock();
	// mockUSDC
	MockERC20 public mockUSDC = new MockERC20("Mock Token", "USDC", 6);
	address[] private _holders = [
		rewardHolder,
		rewardHolder,
		rewardHolder,
		rewardHolder
	];
	uint96[] private _nftQtys = [1, 1, 1, 1];
	string private _mockUrl = "https://mockurl.com/{address}/{data}.json";
	MockRewardToken public mockRewardsToken =
		new MockRewardToken(
			"Mock Tracks",
			"MOCK",
			_holders,
			_nftQtys,
			payable(address(0))
		);

	function setUp() public {
		address swapAddr = deployCode(
			"SonaSwap.sol",
			abi.encode(address(0), address(0), mockUSDC, mockWeth)
		);
		splitMainImpl = new SplitMain(
			mockWeth,
			IERC20(address(mockUSDC)),
			ISonaSwap(swapAddr)
		);
		rewardsBase = new SonaRewards();
		// NOTE: if you get a generic delegatecall error during `setUp` it's probably
		//because the encoded argument counts or types below don't match those in the initialize function interface
		proxy = new ERC1967Proxy(
			address(rewardsBase),
			abi.encodeWithSelector(
				SonaRewards.initialize.selector,
				rewardAdmin,
				mockRewardsToken,
				mockUSDC,
				address(0),
				address(this),
				_mockUrl,
				splitMainImpl
			)
		);

		rewards = SonaRewards(payable(proxy));

		wEthRewardsBase = new SonaRewards();
		wEthProxy = new ERC1967Proxy(
			address(rewardsBase),
			abi.encodeWithSelector(
				SonaRewards.initialize.selector,
				rewardAdmin,
				mockRewardsToken,
				address(0),
				mockWeth,
				address(0),
				_mockUrl,
				splitMainImpl
			)
		);
		wEthRewards = SonaRewards(payable(wEthProxy));
	}

	function test_InitFail() public {
		rewardsBase = new SonaRewards();
		// cannot init with zero-value rewardToken and wEthToken inputs
		vm.expectRevert();
		proxy = new ERC1967Proxy(
			address(rewardsBase),
			abi.encodeWithSelector(
				SonaRewards.initialize.selector,
				rewardAdmin,
				mockRewardsToken,
				address(0),
				address(0),
				address(0),
				_mockUrl
			)
		);
		// cannot init with two non-zero rewardToken and wEthToken inputs
		vm.expectRevert();
		proxy = new ERC1967Proxy(
			address(rewardsBase),
			abi.encodeWithSelector(
				SonaRewards.initialize.selector,
				rewardAdmin,
				mockRewardsToken,
				address(1),
				address(2),
				address(0),
				_mockUrl
			)
		);
	}

	function test_ReceiveFail() public {
		// SonaRewards rejects eth tranfers from non-WETHToken senders
		vm.expectRevert();
		payable(wEthRewards).transfer(1);
		vm.expectRevert();
		payable(rewards).transfer(1);
	}

	function testFuzz_AddRoot(bytes32 _root, uint64 _start, uint64 _end) public {
		vm.assume(_start < _end);
		vm.prank(rewardAdmin);
		vm.expectEmit(true, true, true, true, address(rewards));
		emit RewardRootCreated(1, _root, _start, _end);
		rewards.addRoot(_root, _start, _end);

		vm.prank(rewardAdmin);
		vm.expectEmit(true, false, false, false, address(rewards));
		emit RewardRootInvalidated(1);
		rewards.invalidateRoot(1);
	}

	function testFuzz_ClaimManyRewards(uint8 _treeCount, uint256 _amount) public {
		// things don't really scale well beyond 15k leaves, as far as gas
		// costs or multiple week claims
		//uint256 _leafCount = 20_000;
		uint256 _leafCount = 200;
		vm.assume(_treeCount < 10);
		//uint256 _leafCount = 75_000;
		//vm.assume(_treeCount < 2);
		vm.assume(_amount < _treeCount + _leafCount);
		vm.pauseGasMetering();
		uint256 tokenId = 2;
		uint256 indexToClaim = 2;
		uint256[] memory rootIds = new uint256[](_treeCount);
		uint256[] memory amounts = new uint256[](_treeCount);
		bytes32[][] memory proofs = new bytes32[][](_treeCount);

		bytes32[] memory leaves = new bytes32[](_leafCount);

		uint256 allowance;
		for (uint64 i = 0; i < _treeCount; i++) {
			for (uint256 k = 0; k < _leafCount; k++) {
				// when will solidity get matrix math functionality?
				allowance += _amount + i + k;
				leaves[k] = keccak256(
					bytes.concat(
						keccak256(abi.encode(tokenId, _amount + i + k, i, i + 1))
					)
				);
			}
			mockUSDC.mint(address(this), allowance);
			mockUSDC.approve(address(rewards), allowance);
			bytes32 root = m.getRoot(leaves);
			vm.prank(rewardAdmin);
			rewards.addRoot(root, i, i + 1);
			rootIds[i] = rewards.lastRootId();
			proofs[i] = m.getProof(leaves, indexToClaim);
			amounts[i] = _amount + i + indexToClaim;
		}

		vm.resumeGasMetering();
		vm.prank(rewardHolder);
		rewards.claimRewards(tokenId, rootIds, proofs, amounts);
	}

	function test_ClaimRewards() public {
		// can claim ERC20 funds
		(
			uint256 tokenId,
			uint256[] memory rootIds,
			bytes32[][] memory proofs,
			uint256[] memory amounts
		) = _setUpClaims(rewards);
		vm.prank(rewardHolder);
		vm.expectEmit(true, true, true, true, address(rewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[0], amounts[0]);
		vm.expectEmit(true, true, true, true, address(rewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[1], amounts[1]);
		vm.expectEmit(true, true, false, true, address(mockUSDC));
		emit Transfer(address(this), rewardHolder, amounts[0] + amounts[1]);
		rewards.claimRewards(tokenId, rootIds, proofs, amounts);

		//revert on multiple claim attempts on the same roots
		vm.prank(rewardHolder);
		vm.expectRevert(InvalidClaimAttempt.selector);
		rewards.claimRewards(tokenId, rootIds, proofs, amounts);

		// can claim WETH funds
		assertEq(rewardHolder.balance, 0);
		assertEq(address(mockWeth).balance, 0);
		(tokenId, rootIds, proofs, amounts) = _setUpClaims(wEthRewards);
		payable(address(mockWeth)).transfer(amounts[0] + amounts[1]);
		assertEq(address(mockWeth).balance, amounts[0] + amounts[1]);
		vm.expectEmit(true, true, true, true, address(wEthRewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[0], amounts[0]);
		vm.expectEmit(true, true, true, true, address(wEthRewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[1], amounts[1]);
		vm.expectEmit(true, true, false, true, address(mockWeth));
		emit Transfer(address(0), address(wEthRewards), amounts[0] + amounts[1]);
		vm.prank(rewardHolder);
		wEthRewards.claimRewards(tokenId, rootIds, proofs, amounts);
		assertEq(rewardHolder.balance, amounts[0] + amounts[1]);
	}

	function test_ClaimRewardsToSplit() public {
		// set split address on mock NFT
		address payable splitsAddress = payable(makeAddr("splitsAddress"));
		mockRewardsToken.setSplitAddr(splitsAddress);
		// can claim ERC20 funds
		(
			uint256 tokenId,
			uint256[] memory rootIds,
			bytes32[][] memory proofs,
			uint256[] memory amounts
		) = _setUpClaims(rewards);
		vm.prank(rewardHolder);
		vm.expectEmit(true, true, true, true, address(rewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[0], amounts[0]);
		vm.expectEmit(true, true, true, true, address(rewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[1], amounts[1]);
		vm.expectEmit(true, true, false, true, address(mockUSDC));
		emit Transfer(address(this), splitsAddress, amounts[0] + amounts[1]);
		rewards.claimRewards(tokenId, rootIds, proofs, amounts);

		//revert on multiple claim attempts on the same roots
		vm.prank(rewardHolder);
		vm.expectRevert(InvalidClaimAttempt.selector);
		rewards.claimRewards(tokenId, rootIds, proofs, amounts);

		// can claim WETH funds
		assertEq(rewardHolder.balance, 0);
		assertEq(address(mockWeth).balance, 0);
		(tokenId, rootIds, proofs, amounts) = _setUpClaims(wEthRewards);
		payable(address(mockWeth)).transfer(amounts[0] + amounts[1]);
		assertEq(address(mockWeth).balance, amounts[0] + amounts[1]);
		vm.expectEmit(true, true, true, true, address(wEthRewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[0], amounts[0]);
		vm.expectEmit(true, true, true, true, address(wEthRewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[1], amounts[1]);
		vm.expectEmit(true, true, false, true, address(mockWeth));
		emit Transfer(address(0), address(wEthRewards), amounts[0] + amounts[1]);
		vm.prank(rewardHolder);
		wEthRewards.claimRewards(tokenId, rootIds, proofs, amounts);
		assertEq(splitsAddress.balance, amounts[0] + amounts[1]);
	}

	function test_ClaimRewardsAndDistributeToSplit() public {
		(
			address[] memory accounts,
			uint32[] memory percentAllocations
		) = _createSimpleSplit();
		// set split address on mock NFT
		mockRewardsToken.setSplitAddr(payable(split));
		// can claim ERC20 funds
		(
			uint256 tokenId,
			uint256[] memory rootIds,
			bytes32[][] memory proofs,
			uint256[] memory amounts
		) = _setUpClaims(rewards);
		vm.prank(rewardHolder);
		vm.expectEmit(true, true, true, true, address(rewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[0], amounts[0]);
		vm.expectEmit(true, true, true, true, address(rewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[1], amounts[1]);
		vm.expectEmit(true, true, false, true, address(mockUSDC));
		emit Transfer(address(splitMainImpl), accounts[0], amounts[0] - 1);
		vm.expectEmit(true, true, false, true, address(mockUSDC));
		emit Transfer(address(splitMainImpl), accounts[1], amounts[1] - 1);
		rewards.claimRewardsAndDistributePayout(
			tokenId,
			rootIds,
			proofs,
			amounts,
			accounts,
			percentAllocations
		);

		//revert on multiple claim attempts on the same roots
		vm.prank(rewardHolder);
		vm.expectRevert(InvalidClaimAttempt.selector);
		rewards.claimRewards(tokenId, rootIds, proofs, amounts);

		// TODO set up tests for WETH claims
		/*
		// can claim WETH funds
		assertEq(rewardHolder.balance, 0);
		assertEq(address(mockWeth).balance, 0);
		(tokenId, rootIds, proofs, amounts) = _setUpClaims(wEthRewards);
		payable(address(mockWeth)).transfer(amounts[0] + amounts[1]);
		assertEq(address(mockWeth).balance, amounts[0] + amounts[1]);
		vm.expectEmit(true, true, true, true, address(wEthRewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[0], amounts[0]);
		vm.expectEmit(true, true, true, true, address(wEthRewards));
		emit RewardsClaimed(tokenId, rewardHolder, rootIds[1], amounts[1]);
		vm.expectEmit(true, true, false, true, address(mockWeth));
		emit Transfer(address(0), address(wEthRewards), amounts[0] + amounts[1]);
		vm.prank(rewardHolder);
		wEthRewards.claimRewardsAndDistributePayout(
			tokenId,
			rootIds,
			proofs,
			amounts,
			accounts,
			percentAllocations
		);
		assertEq(accounts[0].balance, amounts[0]);
		assertEq(accounts[1].balance, amounts[1]);
		*/
	}

	function testFuzz_nonHolderReverts(address nonHolder) public {
		vm.assume(nonHolder != rewardHolder);
		vm.assume(nonHolder != address(0));
		(
			uint256 tokenId,
			uint256[] memory rootIds,
			bytes32[][] memory proofs,
			uint256[] memory amounts
		) = _setUpClaims(rewards);
		vm.startPrank(nonHolder);
		vm.expectRevert(
			abi.encodeWithSelector(ClaimantNotHolder.selector, nonHolder, tokenId)
		);
		rewards.claimRewards(tokenId, rootIds, proofs, amounts);
	}

	function test_RevertOnTransferError() public {
		ERC20NoReturnMock mockBadRewardToken = new ERC20NoReturnMock();
		ERC20ReturnFalseMock mockFalseRewardToken = new ERC20ReturnFalseMock();
		(
			uint256 tokenId,
			uint256[] memory rootIds,
			bytes32[][] memory proofs,
			uint256[] memory amounts
		) = _setUpClaims(rewards);
		vm.prank(rewardAdmin);
		rewards.updateIntegrations(
			SonaRewardToken(address(mockRewardsToken)),
			IERC20(address(mockFalseRewardToken)),
			IWETH(address(0)),
			address(0),
			"",
			splitMainImpl
		);

		// expect to revert with our error when a transfer returns `false`
		vm.prank(rewardHolder);
		vm.expectRevert(RewardTransferFailed.selector);
		rewards.claimRewards(tokenId, rootIds, proofs, amounts);

		vm.prank(rewardAdmin);
		rewards.updateIntegrations(
			SonaRewardToken(address(mockRewardsToken)),
			IERC20(address(mockBadRewardToken)),
			IWETH(address(0)),
			address(0),
			"",
			splitMainImpl
		);

		// expect to revert without a message when a transfer returns empty
		vm.prank(rewardHolder);
		vm.expectRevert();
		rewards.claimRewards(tokenId, rootIds, proofs, amounts);
	}

	function test_ClaimLookup() public {
		uint256 tokenId = 2;
		uint64 start = 0;
		uint64 end = 2;
		string[] memory urls = new string[](1);
		urls[0] = _mockUrl;
		vm.expectRevert(
			abi.encodeWithSelector(
				OffchainLookup.selector,
				address(rewards),
				urls,
				abi.encodeWithSelector(
					IRewardGateway.getRewardsforPeriod.selector,
					tokenId,
					start,
					end
				),
				SonaRewards.claimRewards.selector,
				""
			)
		);
		rewards.claimLookup(tokenId, start, end);
	}

	function _setUpClaims(
		SonaRewards _rewards
	)
		private
		returns (
			uint256 tokenId,
			uint256[] memory rootIds,
			bytes32[][] memory proofs,
			uint256[] memory amounts
		)
	{
		// all values here are from scripts/tree.json and scripts/tree2.json
		// to generate this data.
		vm.prank(rewardAdmin);
		_rewards.addRoot(
			0x1c72fd6fe012bda2b12caa9ca5a34e102f4e79664d3e1e2524c2f1d9a984516d,
			0,
			1
		);
		vm.prank(rewardAdmin);
		_rewards.addRoot(
			0x24592ad25cf43069048365e7b15d4e82dfd50b2d00fa1efc860068a7b186ec39,
			1,
			2
		);

		rootIds = new uint256[](2);
		rootIds[0] = 1;
		rootIds[1] = 2;
		bytes32[] memory proof = new bytes32[](2);
		proof[0] = bytes32(
			0xb2bfa1ce84ca850057c842e96a8efda7da28dce25d50616ce6b579a82d756288
		);
		proof[1] = bytes32(
			0xd6391653482705ca5b84440c9f76de84397f286e8890d865c89ddb518fe0b0a9
		);

		bytes32[] memory proof2 = new bytes32[](1);
		proof2[0] = bytes32(
			0x5cf095043a988837ac9bb07020ab3ead4c47fcebba11b89e94e57dd8b6af4ce4
		);

		proofs = new bytes32[][](2);
		proofs[0] = proof;
		proofs[1] = proof2;

		uint256 amount = 2500000000000000000;

		amounts = new uint256[](2);
		amounts[0] = amount;
		amounts[1] = amount;

		mockUSDC.mint(address(this), amount * 2);
		mockUSDC.approve(address(rewards), amount * 2);

		tokenId = 2;
	}
}
