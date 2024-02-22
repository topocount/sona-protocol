import { defineConfig } from "@wagmi/cli"
import { erc, foundry } from "@wagmi/cli/plugins"
import deployments from "./script/deployments"

export default defineConfig({
  out: "abi/generated.ts",
  plugins: [
    foundry({
      deployments,
      artifacts: "dist/artifacts",
      include: ["Sona*.sol/Sona*.json"],
      forge: {
        build: false,
      },
    }),
    erc({
      20: true,
      721: true,
      4626: false,
    }),
  ],
})
