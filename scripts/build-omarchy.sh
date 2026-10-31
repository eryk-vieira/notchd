#!/bin/bash
# Build a self-contained Omarchy plugin folder from hosts/omarchy.
#
# During development hosts/omarchy/core is a symlink to ../../core, which the
# Omarchy shell loads fine but `omarchy plugin validate` (and so plugin
# add/update) rejects. This copies the host with the core inlined into
# dist/eryk.notchd and validates it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/dist/eryk.notchd"

rm -rf "$out"
mkdir -p "$root/dist"
cp -rL "$root/hosts/omarchy" "$out"

omarchy plugin validate "$out"
echo "Built $out"
