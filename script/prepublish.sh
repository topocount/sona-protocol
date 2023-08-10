#!/bin/bash
set -e

pnpm wagmi generate
pnpm tsc
mkdir -p abi/artifacts
cp dist/artifacts/Sona*.sol/Sona*.abi.json abi/artifacts
rm abi/artifacts/Sona*Test.abi.json
rm abi/artifacts/SonaTest*.abi.json
cp dist/artifacts/IERC*.sol/*.abi.json abi/artifacts
