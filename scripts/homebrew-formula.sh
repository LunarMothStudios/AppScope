#!/bin/bash
# Generate a formula only after a real release URL and checksum exist.
set -euo pipefail
if [[ $# -ne 2 ]]; then printf 'Usage: %s HTTPS_RELEASE_ARCHIVE_URL LOCAL_ARCHIVE\n' "$0" >&2; exit 1; fi
release_url="$1"
archive="$2"
if [[ ! "$release_url" =~ ^https://[A-Za-z0-9./_-]+\.tar\.gz$ ]]; then printf 'Expected a plain HTTPS release archive URL.\n' >&2; exit 1; fi
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
    doc.install "docs", "examples", "licenses"
  end

  test do
    assert_match "0.1.0", shell_output("#{bin}/appscope --version")
  end
end
RUBY
