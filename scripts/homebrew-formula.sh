#!/bin/bash
# Generate a formula only after a real release URL and checksum exist.
set -euo pipefail
if [[ $# -ne 2 ]]; then printf 'Usage: %s HTTPS_RELEASE_ARCHIVE_URL LOCAL_ARCHIVE\n' "$0" >&2; exit 1; fi
release_url="$1"
archive="$2"
if [[ ! "$release_url" =~ ^https://[A-Za-z0-9./_-]+\.tar\.gz$ ]]; then printf 'Expected a plain HTTPS release archive URL.\n' >&2; exit 1; fi
archive_name="$(basename "$archive")"
if [[ ! "$archive_name" =~ ^appscope-([0-9]+\.[0-9]+\.[0-9]+)-macos-universal\.tar\.gz$ ]]; then printf 'Expected a versioned AppScope universal archive.\n' >&2; exit 1; fi
version="${BASH_REMATCH[1]}"
if [[ "${release_url##*/}" != "$archive_name" ]]; then printf 'Release URL and local archive filenames must match.\n' >&2; exit 1; fi
if [[ "$(tar -xOf "$archive" "appscope-$version-macos-universal/VERSION")" != "$version" ]]; then printf 'Archive version marker does not match its filename.\n' >&2; exit 1; fi
checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
cat <<RUBY
class Appscope < Formula
  desc "Local app intelligence MCP server for AI agents"
  homepage "${release_url%/releases/download/*}"
  url "$release_url"
  sha256 "$checksum"
  license "MIT"
  depends_on :macos
  depends_on macos: :sonoma

  def install
    bin.install "appscope"
    doc.install "README.md", "CHANGELOG.md", "CONTRIBUTING.md", "SECURITY.md", "LICENSE"
    doc.install "docs", "examples", "assets", "licenses", "BUILD.json", "VERSION"
  end

  test do
    assert_equal "$version", shell_output("#{bin}/appscope --version").strip
  end
end
RUBY
