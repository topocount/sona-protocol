import { defineConfig } from "@wagmi/cli"
import { foundry } from "@wagmi/cli/plugins"

export default defineConfig({
	out: "abi/generated.ts",
	plugins: [
		foundry({
			deployments: {
				SonaRewardToken: {
					11155111: "0x017CFf85774064F096a37214A1b3a423732932B3",
				},
				SonaReserveAuction: {
					11155111: "0x9c2ad06D8379eD690bFc5B32DF6c1FF8d20e8f32",
				},
				SonaRewards: {
					11155111: "0x670478ED5a94A81C5295731Edf5D6A3AFa41fb71",
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
