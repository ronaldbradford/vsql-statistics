#!/usr/bin/env bash
set -euo pipefail

: "${VillageSQL_BUILD_DIR:?VillageSQL_BUILD_DIR must be set}"

mkdir -p build
cmake -S . -B build -DVillageSQL_BUILD_DIR="$VillageSQL_BUILD_DIR"
cmake --build build -- -j "$(( $(getconf _NPROCESSORS_ONLN) - 2 ))"
cmake --install build

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
mkdir -p dist
cp build/vsql_statistics.veb "dist/vsql_statistics-${OS}-${ARCH}.veb"
echo "-- Dist: dist/vsql_statistics-${OS}-${ARCH}.veb"
