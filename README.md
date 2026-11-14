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

    mix polticool.import_money --candidate Thurston "priv/data/PCC-202[56].csv"   # 2025 + 2026 exports
    mix polticool.import_money --candidate Chappell "priv/data/PCC-202[56].csv"
    mix polticool.import_money --candidate Chappell priv/data/money_fallback.json  # hand-entered fallback

Only the candidate's own `Contribution` rows are kept. The filer is derived from the candidate name ("Norman K. Thurston" → "Thurston, Norman"); override it with `--filer`. In-kind gifts count, loans are dropped, refunds stay negative, and rows superseded by an amendment are dropped. Re-imports upsert on `TRAN_ID`, so re-running with `ANTHROPIC_API_KEY` set fills in industry tags.

Donors are normalized, tagged with `claude-haiku-5-5` from a fixed industry list (`ANTHROPIC_API_KEY` required), and stored in `contributions`. `Polticool.Money.top_industries(candidate, 5)` returns `[%{industry, total, share}]`. Columns are matched by header alias (see `Polticool.Money`). `priv/data/money_fallback.sample.json` is a SAMPLE template for hand-entered donors.

## Open data sources

| Data | Source | Files |
| --- | --- | --- |
| Bills, votes, legislator roster | Utah State Legislature, [le.utah.gov](https://le.utah.gov) (e.g. [`legislators.json`](https://le.utah.gov/data/legislators.json)) | ingested live, see above; roster snapshot `priv/data/legislators.json` (2026-11-14) |
| Roll calls, per-member vote positions (and bills) | LegiScan API by LegiScan LLC, [CC BY 4.0](https://legiscan.com/legiscan) | `mix polticool.import_legiscan`, see below |
| Campaign finance (candidate committees) | Utah Lt. Governor's Office, [disclosures.utah.gov](https://disclosures.utah.gov/Search/AdvancedSearch) | `priv/data/PCC-2020.csv` … `PCC-2026.csv` |

**LegiScan import.** le.utah.gov rate-limits scraping, so roll calls come from LegiScan's weekly datasets. Put `LEGISCAN_API_KEY` in `.env` (free tier: 10,000 queries/month) and run:

```
set -a; source .env; set +a
mix polticool.import_legiscan                          # 2026GS and 2025GS
mix polticool.import_legiscan --session 2026GS --force # one session, ignore the stored hash
mix polticool.import_legiscan --zip path/to/dataset.zip # manually downloaded dataset, no API calls
```

A run costs one `getDatasetList` query plus one `getDataset` per session whose dataset hash changed (hashes are stored in `legiscan_datasets`). Bills are upserted by session and number (`HB216` becomes `HB0216`), roll calls are matched to existing votes by bill, chamber and date, and positions are stored per `legislator_code`. LegiScan people are mapped to legislator codes by chamber and district (`Rep`/`HD-062` is house `H`, district 62), confirmed by last name, using the committed roster snapshot `priv/data/legislators.json` (from [le.utah.gov/data/legislators.json](https://le.utah.gov/data/legislators.json), snapshot 2026-11-14, 103 members), because le.utah.gov blocks and times out on scraping. A district hit whose last name differs (a member replaced mid-term) is left unmapped rather than guessed; name matching is only a fallback when LegiScan gives no district. Pass `--refresh-roster` to try the live roster first (it falls back to the snapshot).

Voters who can't be mapped do not abort the run: their positions are skipped, everything else is imported, and the summary lists each unmapped person (`people_id`, name, role, district) and the number of positions skipped (with a prominent warning if THURSNK is among them). To fix them, add `"people_id": "CODE"` entries under `people` in `priv/data/legiscan_people.json` (overrides always win) and re-run; the dataset hash is not recorded while people are unmapped, so the re-run re-imports. `--strict` restores the old behavior: abort and import nothing if any voter is unmapped.

Data: LegiScan API by LegiScan LLC, CC BY 4.0 (https://legiscan.com/legiscan).

**Campaign finance exports.** On disclosures.utah.gov Advanced Search, set Entity Type to *Candidates & Office Holders*, pick a Report Year, click **Find**, then click the year under **Download Data by Year**. Each file holds every candidate committee's filed transactions for that year: columns `FILED, PCC, REPORT, TRAN_ID, TRAN_TYPE, TRAN_DATE, TRAN_AMT, INKIND, LOAN, AMENDS, NAME, PURPOSE, ADDRESS1, ADDRESS2, CITY, STATE, ZIP, INKIND_COMMENTS`. `PCC` is the filing candidate ("Thurston, Norman", "Chappell, David"), `NAME` is the counterparty, and `TRAN_TYPE` marks contributions vs. expenditures. Downloaded 2026-11-14. The site sits behind bot protection, so download by hand in a browser. These are public records, republished unmodified.
