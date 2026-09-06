# Local validation — 2026-09-06

Verified on an Apple Silicon Mac with Swift 6.3.3 and the Xcode macOS SDK.

- `swift test`: 21 passing Swift Testing tests, including a real Swift MCP client
  launching the server executable as a subprocess.
- The same MCP integration test passed against the installed universal executable.
- A second MCP client launched the installed binary and successfully called public
  app lookup, keyword tracking, a two-keyword ranking refresh, daily report, and
  persisted keyword history. The live search covered both a found app and an app
  absent from the returned results; the latter returned null, not an invented rank.
- Public live searches were performed separately from deterministic tests. No
  authenticated Apple account data was used.
- Universal archive built for `x86_64` and `arm64`; both Mach-O slices declare
  macOS 14.0 as their minimum. The ARM slice was executed on the local Mac. An
  Intel Mac and a clean macOS 14 machine have not been used for runtime checks.
- Source and binary installers and private setup configuration verified. New data directory
  permissions are 0700; configuration/database files are 0600.
- Format lint, shell syntax, Git whitespace checks and a source scan for private
  key/token patterns passed. This scan is not an independent security audit.

The release archive has an **ad-hoc development signature**, not a Developer ID
signature or notarization ticket. Source and distribution files are ready locally;
a public GitHub release and Homebrew tap have not been published.

Account-specific Apple Ads/analytics access remains unverified without credentials.
Tests validate synthetic request/response shapes, ES256 signatures, token isolation,
missing popularity, pagination host restrictions, report segment atomicity,
corrections, refund handling, missing metrics, and concurrent tracking limits.
These tests do not establish live account qualification or device search accuracy.

Apple's conversion rate is intentionally unavailable in v0.1; see the data contract.
Hex scheduling is not enabled by this project. A host-side daily job template is
provided separately in `examples/hex-daily-job.md`.
