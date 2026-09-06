#!/bin/bash
set -euo pipefail
archive_root="$(cd "$(dirname "$0")" && pwd)"
install_prefix="${APPSCOPE_PREFIX:-$HOME/.local}"
mkdir -p "$install_prefix/bin"
install -m 755 "$archive_root/appscope" "$install_prefix/bin/appscope"
printf 'Installed: %s/bin/appscope\n' "$install_prefix"
printf 'Run "%s/bin/appscope" setup to create private configuration and MCP settings.\n' "$install_prefix"
