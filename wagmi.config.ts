import { defineConfig } from "@wagmi/cli"
import { foundry } from "@wagmi/cli/plugins"

export default defineConfig({
  out: "abi/generated.ts",
  plugins: [
    foundry({
      deployments: {
        SonaRewardToken: {
					5: "0x08aCA4dCb070a2Ac8c4D89eD521eC9F9a69B43F0",
        },
        SonaReserveAuction: {
					5: "0x683AadCC902d601B54DECb59F59d140FfE27F036",
        },
        SonaRewards: {
					5: "0x4a1392dCc64824cCE63a1756Bd6b676Ba8954092",
        },
      },
      artifacts: "out-via-ir/",
      include: ["Sona*.sol/Sona*.json", "IERC*.sol/*.json"],
      forge: {
        build: false,
      },
    }),
  ],
})
