import {
  createTestClient,
  createWalletClient,
  http,
  numberToHex,
  bytesToHex,
  hexToBytes,
  concat,
  hashTypedData,
} from "viem"
import { mnemonicToAccount } from "viem/accounts"
import { foundry } from "viem/chains"

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

const domain = {
  name: "SonaReserveAuction",
  version: "1",
  chainId: 31337,
  verifyingContract: "0x59Fb3367bC8Ab75A898435F60757cC1Cf1875CD7",
} as const


const directMintDomain = {
  name: "SonaDirectMint",
  version: "1",
  chainId: 31337,
  verifyingContract: "0x34A1D3fff3958843C43aD80F30b94c510645C316",
} as const

const types = {
  MetadataBundle: [
    { name: "tokenId", type: "uint256" },
    { name: "payout", type: "address" },
    { name: "arweaveTxId", type: "string" },
  ],
  MetadataBundles: [{ name: "bundles", type: "MetadataBundle[]" }],
}

const artistBundle = {
  tokenId: concat([
    "0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f",
    numberToHex(68, { size: 12 }),
  ]),
  payout: numberToHex(25, { size: 20 }),
  arweaveTxId: "Hello World!",
} as const

const collectorBundle = {
  tokenId: concat([
    "0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f",
    numberToHex(69, { size: 12 }),
  ]),
  payout: numberToHex(0, { size: 20 }),
  arweaveTxId: "Hello World",
} as const

const arrayBundle = {
  bundles: [artistBundle, collectorBundle],
} as const

async function main() {
  await testClient.setLoggingEnabled(true)
  console.log(domain)
  console.log(types)
  console.log(artistBundle)
  console.log(collectorBundle)
  let sig = await signMessage(artistBundle)
  console.log("artistBundle signature: ", split(sig))
  sig = await signMessage(collectorBundle)
  console.log("collectorBundle signature: ", split(sig))

	const hash = hashTypedData({
		domain: directMintDomain,
		types,
    primaryType: "MetadataBundles",
		message: arrayBundle,
	})

	console.log('message hash: ', hash);

  const arraySig = await signArrayMessage(arrayBundle);
  console.log("array signature: ", split(arraySig));
}

main()


async function signArrayMessage(msg: {
  [key: string]: unknown
}): Promise<`0x${string}`> {
  return walletClient.signTypedData({
    domain: directMintDomain,
    types,
    primaryType: "MetadataBundles",
    message: msg,
  })
}

async function signMessage(msg: {
  [key: string]: unknown
}): Promise<`0x${string}`> {
  return walletClient.signTypedData({
    domain,
    types,
    primaryType: "MetadataBundle",
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
