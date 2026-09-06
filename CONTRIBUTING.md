# Contributing

Use Swift 6+ on macOS 14+ with a matching Xcode SDK. Build with `swift build` and
run `swift test`. Pin dependencies in `Package.resolved`. Keep provider fixtures
synthetic and network-free. Public smoke tests are opt-in and separate from tests.

Keep MCP responses compact and explicit about source, country, time, uncertainty,
and unavailable fields. Do not add fabricated popularity, device-rank claims,
non-additive analytics totals, automatic listing updates or ad spend. Add focused
regressions for source/coverage and failure behavior when changing data handling.

Never commit local databases, private keys, account config, raw authenticated
provider responses, or personal app briefs. `work/`, `dist/` and local credentials
are ignored. Read `docs/DATA-CONTRACT.md` and `SECURITY.md` before adding providers.
