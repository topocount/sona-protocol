import { defineConfig } from "@wagmi/cli"
import { foundry } from "@wagmi/cli/plugins"

export default defineConfig({
	out: "abi/generated.ts",
	plugins: [
		foundry({
			deployments: {
				SonaRewardToken: {
					11155111: "0x549c71Ed66CB7489C68ed530311025994FBaE26a",
				},
				SonaReserveAuction: {
					11155111: "0x4E32acA2a012dC336fE96d50f6408Fa423e34F80",
				},
				SonaRewards: {
					11155111: "0x549c71Ed66CB7489C68ed530311025994FBaE26a",
				},
        SonaDirectMint: {
					11155111: "0x2925901cE249eF0A196225a7D6511612e2cF69cC",
        },
        ERC20Mock: {
          11155111: "0xD22Aa44873B1D0FaFB3ede16b266924EC8578c33",
        },
        Weth9Mock: {
          11155111: "0x62fD7f36BF36df7AE2f7F4d12BC37f8F99Ab735E",
        }

			},
			artifacts: "dist/artifacts",
			include: ["Sona*.sol/Sona*.json"],
			forge: {
				build: false,
			},
		}),
	],
})
