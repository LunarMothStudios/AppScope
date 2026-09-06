# Agent workflows

AppScope provides evidence. The agent supplies research judgment and scheduling.
All examples describe proposed work, not permission to publish metadata or run ads.

## Understand the app and propose audiences

Call `app_profile` and read the description, genre, positioning and owner brief.
Ask the owner for missing purpose, business goal, audiences and differentiators;
store an agreed brief with `save_app_brief`. Do not infer analytics or real user
characteristics from marketing copy.

For a pantry meal planner, useful candidate audiences might be busy households,
people trying to reduce food waste, or cooks who shop infrequently. These are
**hypotheses** grounded in a feature/use case. The next step is testing relevant
search terms and messaging, not claiming those people already use the app.

Suggested prompt:

> Explain the app in one sentence. Propose three plausible audience/use-case
> combinations. For each, cite a feature or owner statement, state what remains
> uncertain, and suggest a few terms people might search. Do not invent audience
> demographics or search volumes.

## Research an initial keyword set

1. Build seeds from the app's core problem, use cases, intended audiences and
   language used by the owner. Distinguish branded terms from generic ones.
2. If Apple Ads is configured, call `keyword_suggestions`. Keep official scores,
   missing values, country, observation date and pagination visible. Otherwise
   proceed with public search and label demand as unknown.
3. Call `analyze_keyword` for relevant candidates. Inspect your position, top
   competitors and their titles, ratings and rating counts. Search API order is
   not a verified device rank.
4. Select a small relevant set with `track_keywords`, then establish a baseline
   using `refresh_rankings`. Keep tracked selections stable during batch pagination.
5. Return a shortlist with relevance, demand evidence, observed competition,
   current position and uncertainties. Do not rank opportunities using a fabricated
   popularity score or assume an absent app/term is an easy opportunity.

AppScope does not offer exhaustive reverse lookup of all competitor keywords.
An agent can generate candidates from competitor titles/descriptions and then
check them; it must not present those candidates as a known competitor keyword list.

## Choose a measurable ASO experiment

Use `aso_strategy` or `daily_report` after collecting data. They return the same
cached briefing in v0.1. The agent can refine its provisional suggestions.

A useful experiment includes the affected app/country, target term or audience,
current evidence and dates, a proposed change, the expected mechanism, a baseline,
and a success measure. For example:

> **Hypothesis:** clearer pantry-focused wording may attract more relevant search
> traffic. **Evidence:** the feature exists in the owner brief; the term has a
> recorded search observation; competing titles explicitly mention pantry use.
> **Proposed change:** draft a relevant subtitle variant for owner review.
> **Measure:** compare the tracked position and available first-time-download data
> for equal 14-day windows after and before release, documenting other marketing,
> releases, seasonality and coverage gaps.

This does not prove the proposed wording will improve ranking. Apple account
metrics are country-level reports, not organic downloads attributed to each keyword.
AppScope neither edits metadata nor validates every App Store metadata limit.
The owner must review listing changes and Apple's current rules before publishing.

## Daily report

Recommended order for a host-owned scheduled job:

1. `setup_status` and `app_profile` to establish context and available providers.
2. `keyword_suggestions` when useful and configured, before new ranking observations
   so scores can attach to them. Keep freshly returned scores separately if an
   existing ranking snapshot is still cached.
3. `refresh_rankings` in batches until `next_offset` is null. Record partial errors;
   retry failed terms with `analyze_keyword` later if appropriate.
4. `app_performance` when App Store Connect is configured, to sync reporting data.
   The default comparison period ends three days ago; check coverage rather than
   assuming the period is complete.
5. `daily_report`; turn the evidence into a concise narrative with changes,
   competitors, uncertainties and at most three experiments. Save the result in
   the host's normal job history.

Use the [copyable daily-job template](../examples/hex-daily-job.md). Configure the
schedule in Hex when its scheduler is ready, or in another host. AppScope does not
run after the host stops unless that host relaunches it for a job.

A first day has no historical comparison. A failed or missed day remains a gap;
the next comparison may be against an earlier date. Report the interval honestly.
Respect the user's notification preference rather than sending the same report
on every unchanged run.

## Multiple apps and countries

Repeat the workflow for each verified app ID and country. Briefs are app-wide;
keyword tracking, ranking snapshots and cached performance are country-specific.
The default is `us`, not the computer's region. There is no `country: all` option
in the v0.1 MCP tools. Run separate country calls and keep their evidence separate.

Prefer one active server and one job at a time. SQLite supports multiple local
processes, but request pacing and Apple Ads token caching are per process.
There is no global scheduler, global rate limiter, or automatic data retention.
