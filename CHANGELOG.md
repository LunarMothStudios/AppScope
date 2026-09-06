# Changelog

Changes to AppScope are recorded here. Version numbers describe the executable,
MCP tools and data behavior together. Preview releases may change these contracts;
check release notes before updating and back up private local data.

## 0.1.0 — local preview, not yet published

- Native Swift stdio MCP server with 16 tools and matching direct CLI calls.
- Public app discovery, metadata and owner-provided audience/purpose briefs.
- Country-specific keyword tracking, observed iTunes Search positions, competitors,
  explained competition estimates and persistent daily comparisons.
- Apple Ads Platform API suggestions with available popularity and a separate
  weekly search-term popularity tool.
- App Store Connect report imports for downloads, engagement and purchases, with
  corrections, coverage, refund adjustments and explicit missing metrics.
- Cached agent briefings and provisional ASO experiments; host-owned daily job
  template.
- Private local credential configuration, in-memory tokens and SQLite history.
- Source installer, universal Mac archive packaging and Homebrew formula generator.
- Public-facing handbook, complete source-derived tool reference, synthetic
  examples and automated documentation checks.

Validation: 21 deterministic tests passed, including an MCP subprocess client;
the installed executable's public workflow was exercised live on Apple Silicon.
See the dated [validation record](docs/VALIDATION.md) for precise coverage.

Known limits: authenticated Apple account qualification, physical-device rank
comparison, Intel/clean macOS 14 runtime checks, Developer ID notarization and
public GitHub/Homebrew publication remain outstanding. Apple conversion rate is
unavailable. No UI, scheduler, exhaustive reverse keyword index or Apple metadata/
campaign write tools are included.
