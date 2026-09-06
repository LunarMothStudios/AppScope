# AppScope

**App intelligence for AI agents.** An open-source Swift MCP server for macOS.
Your agent asks the questions and writes the report; AppScope fetches the data
and remembers what changed. No dashboard or extra app to open.

## What it does

- Finds apps and reads their public store metadata.
- Tracks selected keywords by country, saving your observed position and competitors.
- Explains competition using competitor ratings and keyword matches in titles.
- Queries official Apple Ads keyword suggestions and available popularity scores.
- Imports App Store Connect downloads, engagement, sales and proceeds reports.
- Combines an app brief, intended audiences and collected evidence into an agent
  briefing with provisional ASO experiments and success measures.

Public searches need no credentials. Apple data uses your own local credentials;
there is no AppScope subscription, hosted backend, telemetry, or LLM API key.

## Install

From a Git checkout on a Mac with Swift 6+ and the macOS SDK:

```sh
./scripts/install.sh
"$HOME/.local/bin/appscope" setup
"$HOME/.local/bin/appscope" doctor
```

`setup` prints an MCP configuration with the actual executable path. Add it to
Hex or any host that launches stdio MCP servers. A typical connection is:

```json
{
  "mcpServers": {
    "appscope": {
      "command": "/absolute/path/to/appscope",
      "args": ["serve"]
    }
  }
}
```

Compiled universal Mac archives contain a single executable and `install.sh`.
End users need macOS 14+, but no Swift compiler, Xcode or Python. Public releases
and a Homebrew tap require maintainer publication; local builds do not create them.
See [setup](docs/SETUP.md) and [release packaging](docs/RELEASING.md).

## Ask your agent

> Find my app and confirm its developer. Save a brief about what it does and who
> it helps. Track 20 relevant US keywords. Show my position, who is above me,
> available popularity, and three ASO experiments worth testing.

Start with `search_apps` → `app_profile` → `save_app_brief` → `track_keywords` →
`refresh_rankings`. Call `keyword_suggestions` after Apple Ads is configured and
`app_performance` after App Store Connect is configured. Then use `daily_report`
or `aso_strategy` to give the agent a compact briefing.

The agent's scheduler runs the daily job. AppScope stores history but does not
schedule itself. [Example Hex daily job](examples/hex-daily-job.md).

## MCP tools

| Tool | Purpose |
|---|---|
| `setup_status` | Credential presence and available capabilities |
| `list_apps` / `owned_apps` | Local tracking / Apple account app list |
| `search_apps` / `app_profile` | Public app discovery and positioning |
| `save_app_brief` | Purpose, audiences, differentiators and business goal |
| `track_keywords` / `untrack_keywords` | Select terms by app and country |
| `analyze_keyword` | Position, competitors and explained competition estimate |
| `refresh_rankings` | Refresh tracked terms in batches with partial-error reporting |
| `keyword_history` | Saved observations and dates |
| `keyword_suggestions` | Apple suggestions with available relative popularity |
| `search_term_popularity` | Apple term demand by country, genre and week |
| `app_performance` | Sync analytics and compare reporting periods |
| `daily_report` / `aso_strategy` | Cached evidence and provisional experiments |

You can also call any tool directly:

```sh
appscope call search_apps '{"query":"your app name","country":"us","limit":5}'
```

## Honest limits

**Ranks are observed iTunes Search API positions**, not yet validated against
physical-device App Store searches. Missing means not found in the returned
results; AppScope never invents a rank. It tracks chosen/discovered terms, not
all keywords an app might rank for.

**Competition is an explained estimate.** Popularity comes from Apple when
available; missing values remain unknown. AppScope never fills gaps with fake
search volumes. Audience suggestions are hypotheses, not measured demographics.

**Apple's conversion rate is not reconstructed in v0.1.** Segmented unique counts
are not safely additive. Performance reports include available downloads, event
counts and USD sales/proceeds with date coverage. Missing is not zero, report
latency is explicit, and later corrections replace older data.

No MCP tool changes live metadata or campaigns. Account-specific Apple calls need
live validation with your credentials. See the [data contract](docs/DATA-CONTRACT.md)
and [security model](SECURITY.md).

## Develop

```sh
swift build
swift test
swift run appscope --help
./scripts/package-macos.sh
```

The repository includes deterministic provider fixtures and a real MCP subprocess
test. Build output and local data are ignored. The executable uses the official
[MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk), Foundation,
CryptoKit, SQLite and zlib. [Contributing](CONTRIBUTING.md).

MIT licensed. Not affiliated with Apple.
