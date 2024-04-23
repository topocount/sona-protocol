// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IERC721Bridge {
	function bridgeERC721To(
		address _localToken,
		address _remoteToken,
		address _to,
		uint256 _tokenId,
		uint32 _minGasLimit,
		bytes calldata _extraData
	) external;
}
