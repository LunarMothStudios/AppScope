#!/bin/bash
# Build from a reviewed checkout and install one binary. No sudo or service registration.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
install_prefix="${APPSCOPE_PREFIX:-$HOME/.local}"
cd "$repo_root"
if [[ -d /Applications/Xcode.app/Contents/Developer && -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release --product appscope
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$install_prefix/bin"
install -m 755 "$binary_dir/appscope" "$install_prefix/bin/appscope"
"$install_prefix/bin/appscope" --version
printf '\nInstalled: %s/bin/appscope\n' "$install_prefix"
printf 'Run "%s/bin/appscope" setup to create configuration and print MCP settings.\n' "$install_prefix"
printf 'To uninstall, remove that binary. Your configuration and history are retained.\n'
