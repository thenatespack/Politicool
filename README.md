# Polticool

Utah voter and accountability guide. Each candidate's promises are matched against their legislative record and come with cited receipts and an A–F grade.

## Setup

* Run `mix setup` to install dependencies and create/migrate the database
* Set `ANTHROPIC_API_KEY` for the Claude-backed research pipeline
* Start the server with `mix phx.server` (or `iex -S mix phx.server`) and visit [`localhost:4000`](http://localhost:4000)

## Ingesting legislative data

Bills, votes and roll calls come from le.utah.gov's public endpoints. No token is needed.

```sh
mix polticool.ingest_legislator THURSNK --session 2026GS --session 2025GS --roll-calls --delay 4000
```

* `CODE` is the legislator's roster id from [`le.utah.gov/data/legislators.json`](https://le.utah.gov/data/legislators.json). You can't work it out from the name (Thurston is `THURSNK`, Whyte is `WHYTESL`), so look it up.
* `--session` can be repeated. The default is `2026GS`.
* `--roll-calls` also scrapes each vote's roll call into `vote_positions`.
* `--delay` sets the milliseconds between requests (default `3000`).

**Rate limits:** le.utah.gov returns HTTP 429 after a burst of requests and then stops responding (requests time out) for a while. The task backs off and retries. It's safe to re-run, because bills are upserted and votes that already have roll calls are skipped. If you're blocked, wait and run the same command again.

### Current state (2026-11-14)

The dev database has Thurston's **2025GS** bills and votes, with roll calls for only part of them. **2026GS has not been ingested yet**, because the site blocked us mid-run. Once le.utah.gov responds again, run the command above to finish.

## Backend modules

| Module | Purpose |
| --- | --- |
| `Polticool.Ballot` | Races, candidates, scorecards (Ecto schemas under `ballot/`) |
| `Polticool.Legislature` | Bill JSON ingest, vote parsing, legislator bill search |
| `Polticool.Ballot.RollCall` | `svotes.jsp` roll-call scraping into `vote_positions` |
| `Polticool.Legislators` | Official roster and name → legislator code lookup |
| `Polticool.Anthropic` | Req-based Messages client with Citations and prompt caching |
| `Polticool.Scoring` | Receipt outcomes → Voted/Proposed/Promised bars → A–F grade |

Tests never hit the network. They use `Req.Test` stubs and fixtures in `test/support/fixtures`. Run `mix precommit` before pushing.

## Pledge extraction

Extract a candidate's pledges from their campaign pages (Claude Haiku, verbatim quotes only):

    ANTHROPIC_API_KEY=... mix polticool.extract_pledges CANDIDATE_ID URL [URL...]

Each quote is checked against the fetched page text and dropped if it isn't found verbatim.
Pledges are scored on four rubric criteria (measurable outcome, mechanism, timeframe,
within office power). Fewer than 2 hits marks the pledge vague (`specific: false`),
which lowers the Promised bar in `Polticool.Ballot.scorecard/1`. See `Polticool.Pledges`.

## Money trail

Campaign contributions per candidate, grouped by industry. Facts only: the data states who gave what, never that a donation influenced a vote.

    mix polticool.import_money --candidate Thurston path/to/export.csv
    mix polticool.import_money --candidate Chappell priv/data/money_fallback.json  # hand-entered fallback

Donors are normalized, tagged with `claude-haiku-5-5` from a fixed industry list (`ANTHROPIC_API_KEY` required), and stored in `contributions`. `Polticool.Money.top_industries(candidate, 5)` returns `[%{industry, total, share}]`. The column format of the disclosures.utah.gov "Download Data by Year" CSV export is assumed (header-alias matching, documented in `Polticool.Money`). `priv/data/money_fallback.sample.json` is a SAMPLE template for hand-entered donors.
