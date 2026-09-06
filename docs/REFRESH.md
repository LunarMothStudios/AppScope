# Refresh, recovery and report health

Use `refresh_app` to collect a complete app briefing in one request. It fetches
metadata, optionally queries Apple suggestions in groups of up to 20 seeds,
collects the frozen tracked-keyword selection at depth 200, and optionally syncs
performance. Unconfigured optional providers are explicitly skipped. It then
returns `run` and the same cached `report` available from `daily_report`.

```sh
appscope call refresh_app '{"app_id":"1234567890","country":"us"}'
appscope call refresh_status '{"app_id":"1234567890","country":"us"}'
```

The ID is fictional; replace it. One request may take several minutes for 100
uncached terms. Use a long host timeout or a small `max_steps` (for example 3),
then repeat with the returned `run.run_id`. Supported hosts can request standard
[MCP progress notifications](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/progress).
AppScope sends progress only when the host supplies a progress token.

## Checkpoints and retries

A run saves its keyword list and each step before/after execution. Within the
same UTC date, a new call automatically resumes the latest unfinished run unless
`new_run: true` is supplied. An explicit `run_id` resumes only that app/country's
run with its original options. Successful/skipped steps are retained; failed,
pending or interrupted steps are attempted again. A completed run is returned
without repeating work when explicitly resumed. This is bounded retry per call,
not an infinite background retry loop.

`run.status` is `running`, `paused`, `interrupted`, `partial`, `completed` or
`expired`. `failed_steps`, `remaining_steps`, and step timestamps explain progress.
`completed` means the selected collection steps finished, not that all metrics
or requested keywords were available. Check `report.health` separately.

An OS lock prevents two refresh runs for the same app/country from executing
concurrently against the same data directory. Process exit releases it. A crash
can leave the saved status as `running`; that is a checkpoint, not a live process
indicator. Resume the run to recover. A crash between a provider write and its
checkpoint can repeat that step; ranking caches and analytics import markers
limit duplicate work, but this is not exactly-once network execution.

Runs cannot resume across UTC dates. Start a new run for the new day. Changing
the tracked selection does not change an existing run; its returned briefing
uses the current selection and can flag newly tracked keywords as missing.
Enabling a provider after it was skipped also requires a new run. Popularity
steps request one suggestion page per seed group; they do not claim exhaustive
keyword coverage. Existing cached rankings retain their original popularity;
`report.popularity_evidence` supplies the latest separately dated scores.

## Health

The legacy `report.status: rankings_current` is preserved for compatibility.
Use `report.health` for the whole report. Overall health is `complete`, `partial`
or `unavailable`; each source has its own status and dates.

- Rankings are fresh when all selected terms have observations from today UTC.
- Metadata is fresh for 24 hours.
- Popularity needs a supplied score observed within seven days. These are local
  freshness policies, not guarantees about Apple's update frequency.
- Performance needs recent generation, a recent period end, complete date coverage
  for both comparison periods and the supported metrics. Conversion rate remains
  unavailable and is excluded from completeness requirements.
- Briefs are owner context with an update date; they have no automatic expiry.

Refresh errors remain separate from the age of cached evidence. Unconfigured
providers are explicit gaps. A useful public-only report can have partial health.
No freshness flag proves device-rank accuracy, completeness of Apple's catalog or
causation. [Response guide](RESPONSES.md) · [Data contract](DATA-CONTRACT.md)
