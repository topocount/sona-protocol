# Sona Protocol ![Solidity Version](https://img.shields.io/badge/solidity-%3E%3D%200.8.16-lime)

<div align="left">
  <h4>
    <a href="https://sona.stream">
      Website
    </a>
    <span> | </span>
    <a href="https://contracts.sona.stream">
      Documentation
    </a>
    <span> | </span>
    <a href="https://github.com/sonastream/core/releases">
      Releases
    </a>
    <span> | </span>
    <a href="https://twitter.com/sonastream">
      Twitter
    </a>
  </h4>
</div>

## Table of Contents

- [Sona Protocol ](#sona-protocol-)
  - [Table of Contents](#table-of-contents)
  - [Requirements](#requirements)
  - [Contracts](#contracts)
  - [Getting Started](#getting-started)
    - [Installation](#installation)
    - [Commands](#commands)
    - [Headers](#headers)
    - [Testing](#testing)
    - [Coverage](#coverage)
    - [Environment](#environment)
    - [Deploying](#deploying)
    - [Foundry and type definitions](#foundry-and-type-definitions)
  - [Analyzers](#analyzers)
  - [Maintainers](#maintainers)

## Requirements

- [pnpm](https://pnpm.io/installation)
- [Python3](https://www.python.org/downloads/)
- [pipx](https://github.com/pypa/pipx)
- [Foundry](https://github.com/foundry-rs/foundry) | Or run `./foundry_install.sh`
- git
- make
- [Slither](https://github.com/crytic/slither)
- Solc 0.8.18
- Rust
- [Solstat](https://github.com/0xKitsune/solstat#currently-identified-optimizations-vulnerabilities-and-qa)

## Contracts

```bash
contracts
├── SonaReserveAuction.sol
├── SonaRewardToken.sol
├── SonaRewards.sol
├── access
│   ├── SonaAdmin.sol
│   └── SonaMinter.sol
├── interfaces
│   ├── IRewardGateway.sol
│   ├── ISonaReserveAuction.sol
│   ├── ISonaRewardToken.sol
│   └── IWETH.sol
├── test
│   ├── SonaReserveAuction.t.sol
│   ├── SonaRewardToken.t.sol
│   ├── SonaRewards.t.sol
│   ├── Util.sol
│   ├── access
│   │   └── SonaAdmin.t.sol
│   └── mock
│       ├── ContractBidderMock.sol
│       ├── ERC20Mock.sol
│       └── Weth9Mock.sol
└── utils
    ├── AddressableTokenId.sol
    └── ZeroCheck.sol

```

## Getting Started

### Installation

- With git installed, run `git clone https://github.com/sonastream/core.git`
- `cd` in to `core`
- Run `make install`

### Commands

To see all commands that can be run with `make`, check out the makefile command [table](./Makefile.md)

### Headers

- Install https://github.com/transmissions11/headers
- Run `headers <insert-header>`
- Paste from your clipboard

### Testing

To run tests, run the command `make test`. To change the logs verbosity, update the makefile' command with less or more `v`

### Coverage

To get the test coverage, run `make cover`

### Environment

Fill in your `.env` at your root with:

```
MNEMONIC=
ETHERSCAN_KEY=
TREASURY=
REDISTRIBUTION=
AUTHORIZER=
RPC_URL_GOERLI=
RPC_URL_SEPOLIA=
```

### Deploying

| Command             | Environment                         |
| ------------------- | ----------------------------------- |
| make deploy_local   | Local anvil (http://localhost:8546) |
| make deploy_sepolia | Sepolia                             |

### Foundry and type definitions

When updating foundry modules, commit your changes locally and run `forge install <package-name>`. Then, update the remappings across the following files to allow builds, security scanning and goto definitions to work properly:

- slitherConfig.json
- .vscode/settings.json
- remappings.txt

## Analyzers

The repo comes with two static analyzers for checking for security vulnerabiltiies and gas optimizations

| Command      | Environment                                                      |
| ------------ | ---------------------------------------------------------------- |
| make analyze | Runs solstat and outputs a report to `reports/solstat_report.md` |
| make sec     | Runs slither and outputs a report to stdout                      |

## Maintainers

- [@topocount](https://github.com/topocount)
