#!/bin/bash
# Produce an Intel + Apple Silicon archive, optionally Developer ID signed/notarized.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
if [[ -d /Applications/Xcode.app/Contents/Developer && -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release --arch arm64 --arch x86_64 --product appscope
binary_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
version="$("$binary_dir/appscope" --version)"
staging="$repo_root/dist/appscope-$version-macos-universal"
mkdir -p "$staging/licenses"
install -m 755 "$binary_dir/appscope" "$staging/appscope"
cp LICENSE README.md SECURITY.md CONTRIBUTING.md "$staging/"
cp -R docs examples "$staging/"
cp scripts/install-binary.sh "$staging/install.sh"
for dependency in .build/checkouts/*; do
  for license in "$dependency"/LICENSE "$dependency"/LICENSE.txt "$dependency"/LICENSE.md; do
    if [[ -f "$license" ]]; then install -m 644 "$license" "$staging/licenses/$(basename "$dependency").txt"; break; fi
  done
done
if [[ -n "${APPSCOPE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$APPSCOPE_SIGNING_IDENTITY" "$staging/appscope"
else
  codesign --force --sign - "$staging/appscope"
fi
codesign --verify --strict "$staging/appscope"
lipo -archs "$staging/appscope"
archive="$repo_root/dist/appscope-$version-macos-universal.tar.gz"
tar -czf "$archive" -C "$repo_root/dist" "$(basename "$staging")"
(cd "$repo_root/dist" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
if [[ -n "${APPSCOPE_NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${APPSCOPE_SIGNING_IDENTITY:-}" ]]; then printf 'Notarization requires APPSCOPE_SIGNING_IDENTITY.\n' >&2; exit 1; fi
  ditto -c -k --keepParent "$staging" "$staging.zip"
  xcrun notarytool submit "$staging.zip" --keychain-profile "$APPSCOPE_NOTARY_PROFILE" --wait
  # A bare command-line executable cannot be stapled; Gatekeeper checks the online ticket.
fi
printf 'Archive: %s\n' "$archive"
