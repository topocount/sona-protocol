# Commands

| Command                   | Description                                                                                                   |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- |
| make all                  | Does a clean install, updates dependencies and builds the repo                                                |
| make clean                | Cleans foundry artifacts                                                                                      |
| make install              | Installs git submodules, yarn installs from package.json and installs slither (if you have python3 installed) |
| make update               | Updates git submodules                                                                                        |
| make build                | Builds repo with forge                                                                                        |
| make build_optimized      | Builds repo with forge and IR                                                                                 |
| make build_optimized_size | Builds repo with forge and IR and calculates contract sizes                                                   |
| make coverage             | Gets test coverage for the entire repo                                                                        |
| make lcov                 | Generate LCOV reports to view in the browser                                                                  |
| make gas                  | Cleans foundry artifacts then generates a gas report to stdout                                                |
| make gas_snapshot         | Creates a gas snapshot to .gas_snapshot                                                                       |
| make scripts              | Makes scripts executable                                                                                      |
| make deploy_local         | Deploys to anvil locally (Needs .env)                                                                         |
| make deploy               | Deploys to mainnet (Needs .env)                                                                               |
| make deploy_goerli        | Deploys to goerli (Needs .env)                                                                                |
| make deploy_private       | Deploys to private testnet (Needs .env)                                                                       |
| make test                 | Cleans foundry artifacts and tests the repo                                                                   |
| make test_watch           | Cleans foundry artifacts and tests the repo with the watcher enabled                                          |
| make publish              | Generates wagmi-compatible abis and publishes them to npm (location: /types)                                  |
| make lint                 | Runs the .sol linter                                                                                          |
| make lint_check           | Checks if .sol files are linted                                                                               |
| make fmt                  | Formats .sol files with prettier                                                                              |
| make fmt_check            | Checks if the .sol files are formatted with prettier                                                          |
| make coverage             | Gets test coverage %                                                                                          |
| make node                 | Starts an anvil node daemon process (port: 8545, block time: 15s)                                             |
| make node_kill            | Kills the node                                                                                                |
| make sec                  | Runs the slither static analyzer                                                                              |
| make analyze              | Runs solstat analyzer                                                                                         |
