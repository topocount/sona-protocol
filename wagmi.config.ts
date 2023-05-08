import { defineConfig } from "@wagmi/cli"
import { foundry } from "@wagmi/cli/plugins"

export default defineConfig({
  out: "abi/generated.ts",
  plugins: [
    foundry({
      artifacts: "out-via-ir/",
      include: ["Sona*.sol/Sona*.json", "IERC*.sol/*.json"],
      forge: {
        build: false,
      },
    }),
  ],
})
