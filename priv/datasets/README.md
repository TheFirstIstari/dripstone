# Fetcher corpora

Versioned scraper captures under `priv/datasets/<platform>/<date>.jsonl`
(written by `mix dripstone.refresh <platform> --handle H`, full name
`mix dripstone.datasets.refresh`).

## Line contract

One post object per line:

- `id` (string), `handle` (string, opaque), `text` (string),
  `urls` (list of strings), `published_at` (UTC ISO-8601 or null)
- `fetched_at` (string, required): UTC ISO-8601 capture timestamp
- `source` (string, required): `"<platform>:<handle>"`

## Date naming

Files are named `YYYY-MM-DD.jsonl` for the capture date; readers resolve
the newest file per platform. Seed vs live: the checked-in dated files are
seed corpora for offline tests; live refreshes write a new dated file and
never edit an existing one.
