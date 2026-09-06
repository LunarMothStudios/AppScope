# Trends and competitor changes

`keyword_trends` summarizes saved observations for selected app/country keywords.
It does not make network requests. Use `days: 7` or `days: 30` for the usual
windows; integers from 7 through 30 are accepted. Results page through up to 20
terms per call using `offset`, `batch_size`, and returned `next_offset`.

```sh
appscope call keyword_trends '{"app_id":"1234567890","country":"us","days":7,"batch_size":20,"offset":0}'
```

The app ID is fictional. Refresh first when you want current-day data.

## What is compared

Only iTunes observations at requested depth 200 qualify. The latest observation
on each UTC date is selected before computing averages or competitor persistence;
checking a term repeatedly in one day does not give that day extra weight.

The endpoint comparison is **today versus exactly N calendar days earlier**.
If either date is absent, `rank_change` is null. If a valid observation has no
found rank on either side, the numeric change is also null. AppScope does not
quietly compare with the nearest available week or invent rank 201.

The window average covers the N dates ending today (the baseline endpoint is one
day before that window). `mean_found_position` averages found positions only.
Always read `observed_days`, `found_days`, `not_found_days`, `expected_days` and
`missing_dates`: an average over two found days is not a complete week of data.
Experiment comparisons impose stricter full-coverage requirements before returning
a mean-position difference. See [experiments](EXPERIMENTS.md).

## Change candidates

A rank movement is flagged when its absolute change meets `minimum_change`
(default 3), or crosses the top-10 boundary. Separate event types describe entering
or leaving the actually returned search list. Network failures never become those
events because they do not create not-found observations.

Competitor comparisons use the top three **other apps**, excluding the target.
Full responses show new entries, departed entries, position changes for shared
competitors, and days observed in that sample. A recurring-entry candidate needs
at least two window days in the sample; recurring movement needs that persistence
and at least two positions of movement. Leaving this sample does not mean an app
disappeared from the keyword's complete result list.

Every candidate has a stable app/country/keyword/date/type ID for a host to use
when suppressing duplicate notifications. AppScope does not send alerts, set
notification preferences, estimate statistical significance or claim a sustained
trend from a single endpoint change. The host decides which changes matter.

Daily briefings include compact 7/30-day summaries and at most 20 change candidates,
with a total count revealing more. Request paginated `keyword_trends` for full
dates and competitor evidence. Before enough history exists for a 7-day baseline,
ordinary previous-observation movement is still available in each rank's
`rank_change` with its actual comparison date.
