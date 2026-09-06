# AppScope

**App intelligence for your AI agent.** An open-source Swift MCP server for macOS.

Ask your agent how your apps are doing, where they appear for selected keywords,
who competes with them, and what ASO experiments to try next. AppScope collects
the evidence and remembers changes. You read the answer in your agent—there is
no dashboard or extra app to open.

[Get started](docs/GETTING-STARTED.md) · [Documentation](docs/README.md) ·
[Tool reference](docs/TOOLS.md) · [Contribute](CONTRIBUTING.md)

## What you get

| Capability | Data and requirements |
|---|---|
| App understanding | Public metadata plus your saved purpose, intended audiences and differentiators; no credentials |
| Keyword tracking | Observed search positions by app/country, competitors and local history; no credentials |
| Competition estimates | Explained top-result rating counts and title matches; no credentials |
| Keyword ideas and demand | Apple suggestions and available popularity; your Apple Ads API credentials |
| App performance | Available downloads, engagement, sales/proceeds and date coverage; your App Store Connect API credentials and enabled reports |
| ASO and daily reports | Cached evidence and provisional experiments; your agent reasons, schedules and delivers the report |

AppScope runs locally, stores history in SQLite, and uses your own credentials
when needed. There is no AppScope subscription, hosted backend, telemetry or LLM
API key. The code is [MIT licensed](LICENSE).

## Quick start on a Mac

From an AppScope source checkout, with Swift 6+ and a macOS SDK:

```sh
./scripts/install.sh
"$HOME/.local/bin/appscope" setup
"$HOME/.local/bin/appscope" doctor
```

`setup` prints MCP settings with the actual installed path. Add that connection
to a host that launches local stdio MCP servers. Your agent will discover 16 tools.
Public app searches work immediately; Apple credentials are optional.

For a direct first call:

```sh
"$HOME/.local/bin/appscope" call search_apps '{"query":"your app name","country":"us","limit":5}'
```

Replace the search phrase, then verify the app's developer and URL. The
[first-run walkthrough](docs/GETTING-STARTED.md) takes you from that result to an
app brief, keyword tracking and your first report.

Compiled universal archives need **macOS 14+**, with no compiler, Xcode or Python
on the user's Mac. This is currently a **local v0.1.0 preview**: public GitHub
downloads, a Homebrew tap and Developer ID notarization still need publication/
qualification. No public install URL is claimed yet. See [installation](docs/SETUP.md)
and the [validation record](docs/VALIDATION.md).

## Ask your agent

> Find my app and verify its developer. Save a brief about what it does and whom
> it helps. Track 20 relevant US keywords. Show my observed position, competing
> apps, any available popularity, and three ASO experiments worth investigating.
> Explain the dates and gaps in the evidence.

For recurring use, give your host the [daily job template](examples/hex-daily-job.md).
The job collects fresh data before requesting a cached briefing. Installing
AppScope does not create a scheduler or enable a Hex job.

## Understand the evidence

- **Rank is observed iTunes Search API order.** It has not been validated against
  device App Store results. Missing means absent from the returned results, not
  rank 201. AppScope tracks selected terms, not every keyword an app ranks for.
- **Competition is an estimate.** Popularity comes from Apple when supplied;
  unknown scores remain unknown. Audience ideas are hypotheses, not demographics.
- **Performance has coverage limits.** Missing is not zero, reporting dates can
  lag, and Apple's conversion rate is unavailable in v0.1. Account adapters have
  automated fixture coverage and await live qualification with account access.

No MCP tool edits live listings or campaigns or spends money. Read the
[data contract](docs/DATA-CONTRACT.md), [response guide](docs/RESPONSES.md) and
[security model](SECURITY.md) before relying on an automated report.

## Documentation and development

The [handbook](docs/README.md) covers credentials, CLI/configuration, every tool,
ASO workflows, troubleshooting, architecture and releases. Agent integrations can
use the [JSON tool catalog](examples/tool-catalog.json),
[synthetic calls](examples/tool-calls.json) and [reading index](docs/llms.txt).

```sh
swift build
swift test
swift run appscope-docs --check
```

The docs check validates generated schemas, all 16 examples and relative file
links. Use full Xcode's developer directory if the selected Command Line Tools
cannot run the tests. See [contributing](CONTRIBUTING.md),
[release packaging](docs/RELEASING.md) and [changelog](CHANGELOG.md).

Built with the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk),
Foundation, CryptoKit, SQLite and zlib. Not affiliated with Apple.
