import { defineConfig } from "@wagmi/cli"
import { foundry } from "@wagmi/cli/plugins"

export default defineConfig({
	out: "abi/generated.ts",
	plugins: [
		foundry({
			deployments: {
				SonaRewardToken: {
					5: "0x08aCA4dCb070a2Ac8c4D89eD521eC9F9a69B43F0",
					11155111: "0x017CFf85774064F096a37214A1b3a423732932B3",
				},
				SonaReserveAuction: {
					5: "0x683AadCC902d601B54DECb59F59d140FfE27F036",
					11155111: "0x9c2ad06D8379eD690bFc5B32DF6c1FF8d20e8f32",
				},
				SonaRewards: {
					5: "0x4a1392dCc64824cCE63a1756Bd6b676Ba8954092",
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
