# Popcorn EPG

A Swift CLI tool that fetches Sky TV EPG (Electronic Program Guide) data, enriches
programmes with [TMDb](https://www.themoviedb.org) metadata, and publishes it as
structured JSON for client apps to consume.

The data is regenerated and redeployed **every 12 hours** by GitHub Actions.

## Getting the EPG data

The EPG is published as a set of small, independently-cacheable JSON files behind a
CDN, so clients can sync **incrementally** — download a tiny index, then fetch only
the parts that changed.

**Base URL:** `https://epg.adam-young.co.uk`

| File | Description |
| --- | --- |
| [`/manifest.json`](https://epg.adam-young.co.uk/manifest.json) | Index of every file with a content hash + size. Fetch this first. |
| [`/channels.json`](https://epg.adam-young.co.uk/channels.json) | The channel directory (metadata only, no schedules). |
| `/schedules/<date>.json` | One file per day, e.g. `/schedules/20260611.json`. |

### How to sync (recommended)

```
1. GET /manifest.json
2. For each entry in `files`, compare its `hash` to your locally-stored copy.
3. Download only the entries whose hash is new or changed.
4. Drop any cached day that no longer appears in the manifest's `dates`.
```

Because the guide is a sliding 7-day window, most days are unchanged between syncs —
so after the first download a typical sync only fetches the manifest plus the one new
day. Files are encoded deterministically, so an unchanged day keeps the same hash.

Responses are served with `ETag` and `Cache-Control`, so you can also use conditional
requests (`If-None-Match`) to get cheap `304 Not Modified` responses. The CDN
negotiates `gzip`/`brotli` compression automatically.

### Quick start

```bash
# The index
curl -s https://epg.adam-young.co.uk/manifest.json

# The channel directory
curl -s https://epg.adam-young.co.uk/channels.json

# Today's schedule (date is yyyyMMdd, Europe/London)
curl -s https://epg.adam-young.co.uk/schedules/20260611.json
```

## Data format

### `manifest.json`

```jsonc
{
  "generatedAt": "2026-06-11T06:00:00Z",  // ISO-8601, changes every run
  "dates": ["20260611", "20260612", ...], // the days currently published
  "files": [
    { "path": "channels.json",            "hash": "<sha256>", "bytes": 18234 },
    { "path": "schedules/20260611.json",  "hash": "<sha256>", "bytes": 241003 }
  ]
}
```

`manifest.json` is the only file with a timestamp and is not itself hashed — always
fetch it first to discover what changed.

### `channels.json`

```jsonc
{
  "channels": [
    {
      "sid": "1412",                       // stable Sky service ID
      "name": "Sky Atlantic",
      "logoURL": "https://epgstatic.sky.com/epgdata/1.0/newchanlogos/600/600/skychb1412.png",
      "isHD": false,
      "channelNumbers": [
        { "channelNumber": "108", "subbouquetIDs": [1, 2, 3, ...] }
      ]
    }
  ]
}
```

Programmes reference channels by `sid`.

### `schedules/<date>.json`

```jsonc
{
  "date": "20260611",
  "channels": [
    {
      "sid": "1412",
      "programmes": [
        {
          "title": "The White Lotus",
          "description": "Killer Instincts: Belinda brings Zion to Chloe's expat party...",
          "startTime": 1781125800,         // Unix epoch seconds (UTC)
          "duration": 3900,                // seconds
          "seasonNumber": 3,
          "episodeNumber": 7,
          "isPremiere": true,
          "imageURL": "https://images.metadata.sky.com/pd-image/<uuid>/cover",
          "tmdbTVSeriesID": 111803,
          "genres": ["Comedy", "Drama", "Mystery"],
          "certification": "15",           // GB / BBFC rating
          "voteAverage": 7.604,
          "voteCount": 1424,
          "keywords": ["hotel", "whodunit", ...],
          "watchProviders": ["Sky Go", "Now TV", ...]  // GB streaming providers
        }
      ]
    }
  ]
}
```

**Programme field notes:**

- Optional fields are **omitted** when unknown (not `null`). `isPremiere` only appears
  when `true`.
- A programme has **either** `tmdbMovieID` **or** `tmdbTVSeriesID` (or neither, if the
  title could not be matched on TMDb).
- The TMDb enrichment fields (`genres`, `certification`, `voteAverage`, `voteCount`,
  `keywords`, `watchProviders`) are present only when the title resolved on TMDb.
- `certification` is the **GB/BBFC** rating; `watchProviders` are **GB** streaming
  services (via JustWatch/TMDb).

## Legacy single-file feed

A single monolithic snapshot is also committed to the repository for backward
compatibility, but it is large (~37 MB) and not recommended for incremental clients:

- `https://raw.githubusercontent.com/adamayoung/popcorn-epg/main/epg.json`
- `https://raw.githubusercontent.com/adamayoung/popcorn-epg/main/epg.json.gz` (gzip)

New clients should use the partitioned files above.

## Development

```bash
make build                  # Debug build
make build-release          # Release build
make lint                   # swiftlint --strict + swiftformat --lint
make test                   # Run tests
```

Run locally (writes the partitioned site to `./site`):

```bash
swift run PopcornEPG \
  --days 7 \
  --tmdb-api-key <KEY> \
  --output ./epg.json \
  --cache ./tmdb-cache.json \
  --site-dir ./site
```

| Option | Description |
| --- | --- |
| `--days <n>` | Number of days to fetch (today + n−1). Default `7`. |
| `--tmdb-api-key <key>` | TMDb API key for metadata enrichment (optional). |
| `--cache <path>` | TMDb lookup cache file. Default `./tmdb-cache.json`. |
| `--channels <list>` | Comma-separated channel numbers to fetch, e.g. `101,106,301`. Omit for all. |
| `--site-dir <path>` | Also write the partitioned `manifest.json` / `channels.json` / `schedules/` files. |
| `--output <path>` | Single-file JSON output. Default `./epg.json`. |

See [`CLAUDE.md`](CLAUDE.md) for architecture and contributor notes.

## Hosting

The partitioned site is deployed to [Cloudflare Pages](https://pages.cloudflare.com)
(`popcorn-epg` project) by the `deploy-pages` job in
[`.github/workflows/update-epg.yml`](.github/workflows/update-epg.yml), and served
from `epg.adam-young.co.uk` (alias: `popcorn-epg.pages.dev`).
