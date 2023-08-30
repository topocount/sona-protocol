# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

all: clean install update build analyze

# Clean the repo
clean  :; forge clean && rm -rf node_modules

# Install the Modules
install :; forge install; git submodule update --init --recursive; yarn --cwd lib_v7/v3-periphery install; pnpm install; pip3 install pipx; pipx install slither-analyzer --pip-args '-r requirements.txt'

# Update Dependencies
update :; forge update

# Builds
build : build_swap; forge build --sizes --extra-output-files abi

# Optimized build
build_optimized :; FOUNDRY_PROFILE=optimized forge build --extra-output-files abi

# Optimized build
build_optimized_size :; FOUNDRY_PROFILE=optimized forge build --sizes --extra-output-files abi

# Test Coverage
coverage :; doppler run -- forge coverage --report summary

lcov:; doppler run -- forge coverage --report lcov && genhtml lcov.info --output-dir coverage

# Gas report
gas :; forge clean && forge test --gas-report

# Gas Snapshot to .gas-snapshot
gas_snapshot :; forge clean && forge snapshot

# chmod scripts
scripts :; chmod +x ./scripts/*

# deploy with doppler env
deploy_private_doppler:; doppler run -- make deploy_private

# deploy local
deploy_local :; FOUNDRY_PROFILE=optimized forge script ./scripts/solidity/Deploy.s.sol:Deployer \
	--fork-url "http://localhost:8545" \
	--private-key ${PRIVATE_KEY} \
	-vvvv \
	--broadcast

deploy_private :; FOUNDRY_PROFILE=optimized forge script script/solidity/Deploy.s.sol:Deployer \
	--slow \
	-vvvv \
	--skip-simulation \
	--broadcast \
	--rpc-url ${RPC_URL}

deploy_goerli :; FOUNDRY_PROFILE=optimized forge script script/solidity/Deploy.s.sol:Deployer \
	--rpc-url ${RPC_URL_GOERLI} \
	-vvv \
	--slow \
	--skip-simulation \
	--broadcast \
	--chain-id 5

deploy_sepolia :; FOUNDRY_PROFILE=optimized forge script script/solidity/Deploy.s.sol:Deployer \
	--rpc-url ${RPC_URL_SEPOLIA} \
	-vvv \
	--slow \
	--skip-simulation \
	--broadcast \
	--chain-id 11155111

deploy_mainnet :; forge script ./script/solidity/Deploy.s.sol \
	--optimizer-runs 10000 \
	--rpc-url ${RPC_URL} \
	--private-key ${PRIVATE_KEY} \
	-vvv \
	--broadcast \
	--chain-id 1 \
	--etherscan-api-key ${ETHERSCAN_API_KEY} \
  --verify

# Tests
test : build_swap test_swap; doppler run -- forge test -vvv # --ffi # enable if you need the `ffi` cheat code on HEVM

# build SonaSwap
build_swap :; FOUNDRY_PROFILE=swap forge build

# test SonaSwap
test_swap :; FOUNDRY_PROFILE=swap doppler run -- forge test

test_watch : build_swap test_swap; doppler run -- forge test -w -vvv # --ffi # enable if you need the `ffi` cheat code on HEVM

# Docs buld
docs_build :; rm -rf docs && forge doc --build

# Docs serve
docs_serve :; forge doc --serve

# Lint
lint :; pnpm lint

# Lint check
lint_check :; pnpm lint:check

# Fmt
fmt :; pnpm fmt

# Fmt check
fmt_check :; pnpm fmt:check

# Local node -- produces a block every 15 seconds
node :; anvil --block-time 15 > /dev/null 2>&1 &

# Local node eth fork
node_fork :; anvil --fork-url ${RPC_URL} > /dev/null 2>&1 &

node_kill :; killall anvil

# Security
sec :; slither . --config slitherConfig.json

# Publish
publish : lint_check build_optimized; pnpm publish --no-git-checks

# Analyze
analyze :; solstat --path ./contracts --toml ./solstat.toml && mv solstat_report.md ./reports/solstat_report.md
