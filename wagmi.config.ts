import { defineConfig } from "@wagmi/cli"
import { foundry } from "@wagmi/cli/plugins"

export default defineConfig({
	out: "abi/generated.ts",
	plugins: [
		foundry({
			deployments: {
				SonaRewardToken: {
					11155111: "0x92dCAfd7c5C402fb40F1dA12bE2911DF3C0727fd",
				},
				SonaReserveAuction: {
					11155111: "0x6D61a1EbB21a81EE1b8844Db6C45076aCe378ae0",
				},
				SonaRewards: {
					11155111: "0xD07eE77Aaf92bd070E0718D750E2E9E17ae7163C",
				},
			},
			artifacts: "dist/artifacts",
			include: ["Sona*.sol/Sona*.json"],
			forge: {
				build: false,
			},
		}),
	],
})
