# Record and measure ASO experiments

An experiment records what changed, why, the UTC start date, selected keywords
and equal before/after windows. AppScope saves an initial baseline from existing
local observations and analytics. It does not collect data, edit a listing or
automatically track these keywords when recording an experiment. Set up daily
tracking first so the before and after periods have observations.

## Record a change

Use `record_experiment` after the change begins. A host-generated stable UUID
makes retries safe: the same ID/definition returns the existing record, while
different details using that ID are rejected. Omitting the ID creates a new
record each time, so keep the returned ID before retrying.

```json
{
  "app_id": "1234567890",
  "country": "us",
  "experiment_id": "11111111-1111-4111-8111-111111111111",
  "title": "Clearer pantry subtitle",
  "hypothesis": "Explicit pantry wording may attract more relevant searches",
  "change": "Released a pantry-focused subtitle",
  "start_date": "2026-08-30",
  "window_days": 14,
  "keywords": ["pantry meal planner"],
  "notes": "Document any simultaneous campaigns or pricing changes here"
}
```

The app ID, UUID and date are illustrative. Use your own values. The start must
be a real date within the past year, no later than today UTC. Windows are 7–30
days and experiments contain 1–20 normalized unique terms. Their term selection
remains fixed even if your daily tracking changes.

For a 14-day window beginning August 30, the baseline covers August 16–29 and
the after period covers August 30–September 12, inclusive. A change partway
through its start day can affect the comparison; note that limitation.

## Review results

Call `list_experiments` to find IDs/revisions, then `experiment_report` with the
app, country and experiment ID. The result includes:

- `experiment.baseline_at_creation`: original evidence, preserved unchanged;
- `baseline` and `after`: recalculated local evidence for the fixed windows;
- `baseline_changed_since_recorded`: whether later collection/corrections changed
  the recalculated baseline;
- `keyword_comparisons`: daily coverage and mean observed positions;
- `performance_changes`: after minus before for supported metrics when comparable.

Only the last saved depth-200 iTunes observation on each UTC day counts. A mean
position difference requires a found rank on every date in both windows. Missing
or not-found days remain visible and produce a null difference, never rank 201.
Positive mean-position change indicates improvement because it is before minus
after. Analytics differences require complete matching report date coverage,
country rows and an available metric. Explicit zero is retained.

Report status is `collecting` until the after window's last UTC day ends, then
`comparable` if the implemented coverage requirements pass, or `incomplete` if
they do not. Apple report latency may keep data incomplete beyond the window.
No automatic statistical-significance test or causal attribution is claimed.

## Notes and lifecycle

`update_experiment` accepts a current `expected_revision`, optional replacement
notes, and status `running`, `completed` or `stopped`. At least one update field
is required. A stale revision is rejected: read the record again and reconcile
the newer notes before retrying. The revision changes after every successful
update, so retrying an already successful update with the old revision is rejected.

Status records the owner's workflow decision; marking completed does not prove
that an experiment worked or force the measurement report to become comparable.
The original hypothesis, change, dates and captured baseline remain immutable.
Record a new experiment if its definition needs to change.

Account data is country-level, not keyword-attributed organic acquisition. Other
campaigns, releases, seasonality and missing data can explain observed changes.
The agent should explain those limits when deciding the next experiment.
