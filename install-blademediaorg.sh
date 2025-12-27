#!/usr/bin/env bash
set -euo pipefail

# Back-compat wrapper for the old name.
# Prefer running: ./install-mediabladeorg.sh

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "${script_dir}/install-mediabladeorg.sh" "$@"
