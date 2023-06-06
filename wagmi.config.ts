import { defineConfig } from "@wagmi/cli"
import { foundry } from "@wagmi/cli/plugins"

export default defineConfig({
  out: "abi/generated.ts",
  plugins: [
    foundry({
      deployments: {
        SonaRewardToken: {
          888: "0x123e2EE7dBB06DC777245Ebe8daba2a57c1432fE",
        },
        SonaReserveAuction: {
          888: "0xE53E1068e3E3f86AD05481667524EF48fC1C6419",
        },
        SonaRewards: {
          888: "0x6D61a1EbB21a81EE1b8844Db6C45076aCe378ae0",
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
