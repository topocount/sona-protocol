#!/bin/bash
set -e

pnpm wagmi generate
mkdir -p abi/artifacts
cp out-via-ir/Sona*.sol/Sona*.abi.json abi/artifacts
cp out-via-ir/IERC*.sol/*.abi.json abi/artifacts
