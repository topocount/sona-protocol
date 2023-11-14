# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

all: clean install update build analyze

# Clean the repo
clean  :; forge clean && rm -rf node_modules

# Install the Modules
install :; forge install; git submodule update --init --recursive; yarn --cwd lib_v7/v3-periphery install; pnpm install;

install_python :; pip3 install pipx; pipx install slither-analyzer --pip-args '-r requirements.txt'

install_dev : install install_python;

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

deploy : deploy_libs; forge script ./script/solidity/Deploy.s.sol:Deployer \
	--rpc-url ${RPC_URL} \
	-vvv \
	--broadcast

deploy_libs :; forge script ./script/solidity/Deploy_libraries.s.sol:Deployer \
	--rpc-url ${RPC_URL} \
	-vvv \
	--broadcast

deploy_local :; forge script ./script/solidity/Deploy.s.sol:Deployer \
	--rpc-url "http://localhost:8546" \
	-vvv \
	--broadcast

deploy_swap_local :;FOUNDRY_PROFILE=swap forge script ./script/solidity_v7/Deploy_Swap.s.sol:DeploySwap \
	--rpc-url "http://localhost:8546" \
	-vvv \
	--broadcast \
	--chain-id 31337

deploy_libs_local :; forge script ./script/solidity/Deploy_libraries.s.sol:Deployer \
	--rpc-url "http://localhost:8546" \
	-vvv \
	--broadcast \
	--chain-id 31337

deploy_libs_sepolia :; forge script ./script/solidity/Deploy_libraries.s.sol:Deployer \
	--rpc-url ${RPC_URL_SEPOLIA} \
	-vvv \
	--broadcast \
	--verify \
	--chain-id 11155111

deploy_goerli :; forge script script/solidity/Deploy.s.sol:Deployer \
	--rpc-url ${RPC_URL_GOERLI} \
	-vvv \
	--slow \
	--skip-simulation \
	--chain-id 5

deploy_sepolia :; forge script script/solidity/Deploy.s.sol:Deployer \
	--rpc-url ${RPC_URL_SEPOLIA} \
	-vvv \
	--broadcast \
	--verify \
	--chain-id 11155111

deploy_mainnet :; FOUNDRY_PROFILE=optimized forge script ./script/solidity/Deploy.s.sol \
	--rpc-url ${RPC_URL} \
	-vvv \
	--chain-id 1 \
  --verify

upgrade_auction_sepolia :; FOUNDRY_PROFILE=optimized forge script script/solidity/Upgrade.s.sol:UpgradeAuction \
	--rpc-url ${RPC_URL_SEPOLIA} \
	-vvv \
	--slow \
	--broadcast \
	--chain-id 11155111

upgrade_reward_token_sepolia :; FOUNDRY_PROFILE=optimized forge script script/solidity/Upgrade.s.sol:UpgradeRewardToken \
	--rpc-url ${RPC_URL_SEPOLIA} \
	-vvv \
	--slow \
	--broadcast \
	--chain-id 11155111

upgrade_rewards_sepolia :; FOUNDRY_PROFILE=optimized forge script script/solidity/Upgrade.s.sol:UpgradeRewards \
	--rpc-url ${RPC_URL_SEPOLIA} \
	-vvv \
	--slow \
	--broadcast \
	--chain-id 11155111

upgrade_auction_local :; FOUNDRY_PROFILE=optimized forge script script/solidity/Upgrade.s.sol:UpgradeAuction \
	--rpc-url "http://localhost:8546" \
	-vvv \
	--slow \
	--broadcast \
	--chain-id 31337

upgrade_reward_token_local :; FOUNDRY_PROFILE=optimized forge script script/solidity/Upgrade.s.sol:UpgradeRewardToken \
	--rpc-url "http://localhost:8546" \
	-vvv \
	--slow \
	--broadcast \
	--chain-id 31337

upgrade_rewards_local :; FOUNDRY_PROFILE=optimized forge script script/solidity/Upgrade.s.sol:UpgradeRewards \
	--rpc-url "http://localhost:8546" \
	-vvv \
	--slow \
	--broadcast \
	--chain-id 31337

# Tests
test : build_swap test_swap; FOUNDRY_PROFILE=test doppler run -- forge test -vvv # --ffi # enable if you need the `ffi` cheat code on HEVM

# build SonaSwap
build_swap :; FOUNDRY_PROFILE=swap forge build

# test SonaSwap
test_swap :; FOUNDRY_PROFILE=swap doppler run -- forge test

test_watch : build_swap test_swap; FOUNDRY_PROFILE=test doppler run -- forge test -w -vvv # --ffi # enable if you need the `ffi` cheat code on HEVM

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

# Local node -- produces a block every 14 seconds
node :; anvil -p 8546 --block-time 14 --mnemonic "${MNEMONIC}"

# Local node eth fork
node_fork_mainnet :; anvil -p 8546 --fork-url ${MAINNET_FORK_RPC_URL}
node_fork_sepolia :; anvil -p 8546 --fork-url ${RPC_URL_SEPOLIA}

node_kill :; killall anvil

# Security
sec :; slither . --config slitherConfig.json

# Publish
publish : lint_check build_optimized; pnpm publish --no-git-checks

# Analyze
analyze :; solstat --path ./contracts --toml ./solstat.toml && mv solstat_report.md ./reports/solstat_report.md
