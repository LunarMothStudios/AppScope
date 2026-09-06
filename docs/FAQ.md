# Frequently asked questions

## Is this another app I have to open?

No. AppScope is a command-line executable your MCP host starts as needed. You ask
your agent for an answer and read it there. There is no required dashboard.

## Where does the MCP server run?

On your Mac, as a child process of the MCP host. They exchange messages through
stdin/stdout. There is no port to configure. Each user supplies their own Apple
credentials locally when they want account-only data.

## Do I need Swift, Xcode, Python, or an LLM key?

A compiled universal release needs macOS 14+ and a compatible MCP host; it needs
none of those development runtimes. Building from source needs Swift 6+ and a
macOS SDK. AppScope does not call an LLM: your existing agent provides reasoning.

## What can I do immediately without Apple credentials?

Find a public app, read its metadata, save a purpose/audience brief, select
keywords, collect observed search positions and competitors, and build local
history. The agent can use that evidence for provisional ASO experiments. See
[getting started](GETTING-STARTED.md).

## Does it completely replace Astro or another ASO service?

It covers a focused workflow for agent users. It does not provide an exhaustive
reverse keyword index, verified device search ranks, guaranteed popularity for
every term, measured audience demographics, or a mature hosted analytics product.
Evaluate the actual data against your needs using the [data contract](DATA-CONTRACT.md).
An observed API position must not be advertised as a qualified device ranking.

## Does “competition” mean Apple's keyword difficulty?

No. It is AppScope's transparent estimate based on top-result rating counts and
keyword substrings in titles. The response includes the model, inputs and missing
data. It does not predict the probability of ranking or estimate downloads.

## Does it find every keyword my app ranks for?

No. You or your agent choose phrases, optionally assisted by Apple suggestions.
AppScope tests those phrases and records what was returned. It has no complete
reverse index of the App Store.

## Does running on a Mac mean it tracks Mac App Store rankings?

The executable runs on macOS. The current public search adapter uses Apple's
`software` entity for the mobile app catalog; there is no separate
`macSoftware` search mode or device selector in v0.1. Do not claim Mac App Store
rank coverage from these results. Account analytics depend on the app and reports
available through your App Store Connect access.

## Can I use it for competitors or several apps/countries?

Public searches work for public apps. Local tracking is separate for each app and
country; the owner brief is shared across countries for an app. Each app/country
can track up to 100 terms. Private analytics require access to the corresponding
Apple account. Use explicit countries; an `all` country aggregate is not supported.

## Is it free and fully open source?

The code is MIT licensed. AppScope has no subscription, hosted account, telemetry,
or paid model dependency. Your agent service and any Apple account access have
their own requirements. Keys, local history and private reports are not part of
the source or distribution.

## Can an agent publish changes or buy ads?

No MCP tool can edit Apple listings or campaigns or spend money. Some tools write
local briefs, selections and observations. The separate CLI-only
`enable-reports APP_ID --confirm` command creates an Apple analytics report
request using an Admin key; it does not change a listing.

## How does a daily report work?

The host schedules data collection, calls `daily_report`, writes the narrative
and stores/delivers it. `daily_report` and `aso_strategy` are the same cached
briefing in v0.1 and do not refresh data themselves. Use the [daily job template](../examples/hex-daily-job.md).

## What can AppScope tell me about audiences?

It preserves your description of whom the app helps and gives the agent store
metadata to reason from. Additional audience/use-case ideas are hypotheses. It
does not infer actual user demographics from ratings, keywords or app descriptions.

## Can it give me conversion rate, retention, or keyword-level revenue?

Apple's conversion rate is always unavailable in v0.1 because unique counts are
not safely additive in the imported rows. Retention, subscriptions, cohorts and
keyword-attributed revenue are not implemented. Supported performance fields and
coverage rules are in the [response guide](RESPONSES.md).

## Does it work offline?

Saved briefs, tracking, history and cached briefings are local. New public data,
Ads suggestions and analytics imports need network access. Offline data retains
its original dates; a newly generated briefing is not proof of newly fetched data.

## Can I install it with Homebrew today?

The repository has packaging and formula-generation scripts, but a public release
and tap still need publication. Until a real download/tap URL is published, use
the source installer. See the [release guide](RELEASING.md) for maintainer steps.
