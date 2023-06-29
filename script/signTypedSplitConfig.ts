import {
	createTestClient,
	createWalletClient,
	http,
	numberToHex,
	bytesToHex,
	hexToBytes,
	createPublicClient,
	getContract,
	hexToBigInt,
	concat,
} from "viem"
import { HDAccount, mnemonicToAccount } from "viem/accounts"
import { foundry } from "viem/chains"
import SonaReserveAuction from "../out-via-ir/SonaReserveAuction.sol/SonaReserveAuction.json"
import { sonaReserveAuctionABI } from "../abi/generated"

const testClient = createTestClient({
	chain: foundry,
	mode: "anvil",
	transport: http(),
})

const account = mnemonicToAccount(
	"test test test test test test test test test test test junk",
	{ accountIndex: 0 },
)

console.log({ account })
const walletClient = createWalletClient({
	account,
	chain: foundry,
	transport: http(),
})

const publicClient = createPublicClient({
	chain: foundry,
	transport: http(),
})

const domain = {
	name: "SplitMain",
	version: "1",
	chainId: 31337,
	verifyingContract: "0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f",
} as const

const types = {
	SplitConfig: [
		{ name: "split", type: "address" },
		{ name: "accounts", type: "address[]" },
		{ name: "percentAllocations", type: "uint32[]" },
	],
}

const artistBundle = {
	split: "0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3",
	accounts: [numberToHex(1, {size: 20}), numberToHex(2, {size: 20})],
	percentAllocations: [5e5, 5e5],
} as const


async function main() {
	await testClient.setLoggingEnabled(true)
	console.log(domain)
	console.log(types)
	console.log(artistBundle)
	const sig = await signMessage(artistBundle)
	console.log("signature: ", split(sig))
}

main()

async function signMessage(msg: {
	[key: string]: unknown
}): Promise<`0x${string}`> {
	return walletClient.signTypedData({
		domain,
		types,
		primaryType: "SplitConfig",
		message: msg,
	})
}

function split(
	signature: `0x${string}`,
): [number, `0x${string}`, `0x${string}`] {
	const raw = hexToBytes(signature)
	switch (raw.length) {
		case 65:
			return [
				raw[64], // v
				bytesToHex(raw.slice(0, 32)) as `0x${string}`, // r
				bytesToHex(raw.slice(32, 64)) as `0x${string}`, // s
			]
		default:
			throw new Error("Invalid signature length, cannot split")
	}
}
