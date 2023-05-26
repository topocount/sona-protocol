#!/bin/bash
set -e

pnpm wagmi generate
pnpm tsc
mkdir -p abi/artifacts
cp out-via-ir/Sona*.sol/Sona*.abi.json abi/artifacts
rm abi/artifacts/Sona*Test.abi.json
rm abi/artifacts/SonaTest*.abi.json
cp out-via-ir/IERC*.sol/*.abi.json abi/artifacts
