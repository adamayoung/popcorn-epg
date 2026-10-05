# Popcorn EPG

Swift CLI tool that fetches Sky TV EPG (Electronic Program Guide) data, enriches programmes with TMDb metadata, and outputs structured JSON.

## Build & Run

```bash
make build                  # Debug build
make build-release          # Release build
make build-linux            # Linux build via Docker (swift:6.2.0-jammy)
make build-linux-release    # Linux release build via Docker
```

```bash
swift run PopcornEPG --output ./epg.json --days 7 --tmdb-api-key <KEY> --cache ./tmdb-cache.json
```

Options:

- `--channels 101,106,301` — fetch only the given channel numbers (omit for all).
- `--site-dir ./site` — also write partitioned files for static hosting / incremental
  client sync: `manifest.json` (per-file SHA-256 index), `channels.json`,
  `regions.json`, and `schedules/<date>.json`. Clients fetch the manifest, then only
  the changed partitions.

Both `--output` and `--site-dir` also emit a static `regions.json` (the `Region.all`
lookup table). Each channel number records the `(bouquet, subBouquet)` regions it
appears in, so a client joins those pairs to `regions.json` to label/filter the guide
by region.

## Lint & Format

```bash
make format                 # Auto-fix with swiftlint + swiftformat
make lint                   # Strict lint check (swiftlint --strict + swiftformat --lint)
```

Always run `make lint` before committing. Warnings are treated as errors (`-Xswiftc -warnings-as-errors`).

## Test

```bash
make test                   # Run tests (macOS)
make test-linux             # Run tests in Docker
```

## Code Style

- Swift 6.2, macOS 13+ minimum
- 120 character line width
- 4-space indentation
- SwiftFormat and SwiftLint enforced (see `.swiftformat` and `.swiftlint.yml`)
- File headers: copyright Adam Young 2026
- `force_unwrapping` is a lint error — avoid `!`

## Architecture

- **Entry point**: `Sources/PopcornEPG/PopcornEPG.swift` — `@main` async command using ArgumentParser
- **Models**: `Channel`, `Programme`, `Bouquet`, `EPGData`
- **Networking**: `SkyAPIClient` with retry/backoff and its own `URLSession`; `AsyncSemaphore` limiting to 20
  concurrent requests, with the session's per-host connection limit set to match
- **Services**: `EPGService` (orchestration), `TMDbLookupService` (metadata enrichment), `TMDbCache` (JSON cache), `SiteWriter` (partitioned static-site output)
- **DTOs**: `SkyServicesResponse`, `SkyScheduleResponse`

### File-level reference

Source tree (`Sources/PopcornEPG/`):

- `PopcornEPG.swift` — `@main` `AsyncParsableCommand`. Flags: `--output`, `--days` (default 7),
  `--tmdb-api-key`, `--cache` (default `./tmdb-cache.json`), `--channels`, `--site-dir`.
  Pipeline in `run()`: generate dates (`yyyyMMdd`, `Europe/London`) → `fetchAllChannels()` →
  filter by `--channels` → `fetchSchedules()` → optional TMDb enrichment → write single-file
  JSON (`--output`, plus a zlib `.gz`, plus `regions.json` in the same dir — see
  `writeSingleFile`) and/or partitioned site (`--site-dir`). Single-file outputs use
  `atomicWrite` (write `.tmp`, remove, move). zlib via `Compression` on Apple, python3
  fallback on Linux. JSON encoded with `.sortedKeys`.
- `Models/`
  - `Channel.swift` — `Channel` (sid, name, logoURL, isHD, `type: ChannelType`,
    `channelNumbers: [ChannelNumberMapping]`, `schedules: [DaySchedule]`), `ChannelType`
    (`tv`/`radio` string enum), `ChannelNumberMapping` (channelNumber, `regions: [RegionRef]`),
    `RegionRef` (`bouquet`, `subBouquet`; `Hashable`), `DaySchedule` (date, programmes). All `Encodable`.
    Note `channelNumber` is a **string** and must stay one — radio uses a zero-padded band
    (`"0101"`–`"0141"`) that collides with TV (`"101"`–`"141"`) if parsed as `Int`.
  - `Region.swift` — `Region` (bouquet, subBouquet, name, nation, isHD) + `RegionsFile` wrapper
    (`{ regions: [Region] }`) for `regions.json`. `Region+all.swift` holds the static
    (bouquet, subBouquet) → region table (one entry per HD and SD pair; see mapping below).
  - `Programme.swift` — `Encodable` with a hand-written `encode(to:)` that omits nil/false fields
    (e.g. `isPremiere` only encoded when true). TMDb fields are mutable vars filled during enrichment.
  - `Bouquet.swift` — `Bouquet { id: Int; name: String }`. `Bouquet+all.swift` lists 5 bouquets:
    4101 Sky Default, 4109 Sky Extra, 4097 Sky Primary, 4105 Sky Secondary, 4110 Sky Tertiary.
  - `EPGData.swift` — `{ dates: [String]; channels: [Channel] }`, the single-file output root.
- `Networking/`
  - `SkyAPIClient.swift` — base `https://awk.epgsky.com/hawk/linear`. `fetchServices(bouquetID:subbouquetID:)`
    → `/services/{b}/{s}`; `fetchSchedule(date:sids:)` → `/schedule/{date}/{sid,sid,…}` (comma-separated,
    max 20 SIDs). 3 retries, exponential backoff, retries on 429/500/502/503/504. `init(maxConnectionsPerHost:)`
    builds a dedicated `URLSession`: the API is HTTP/1.1 only and URLSession's default of 6 connections per
    host would otherwise cap concurrency below the semaphore limit.
  - `SkyAPIError.swift` — `invalidURL`, `httpError(statusCode:)`, `decodingError`.
- `Services/`
  - `EPGService.swift` — orchestration. `fetchAllServices()` probes every `Bouquet.all` × subbouquet
    `1...20` (`maxSubbouquetID`) in a task group, swallowing failures, tagging each service with a
    `RegionRef(bouquet, subBouquet)`. `buildChannels()` dedupes by `service.sid`, skips adult
    (`sg == 18`), and groups channel numbers → the `RegionRef`s they appear in (bouquet + subbouquet
    both preserved). `fetchAllSchedules()` splits channels into batches of 20 SIDs
    (`maxSIDsPerScheduleRequest`) and fans out one request per batch/date under a 20-permit
    `AsyncSemaphore`, matching response entries to channels by SID. If a batch request fails, its
    channels are fetched one at a time so a bad channel only loses itself. `init(maxConcurrentRequests:)`
    creates the `SkyAPIClient` with the same number as its connection limit. `cleanDescription` strips
    `[AD][HD][S]…` feature tags via regex.
  - `TMDbLookupService.swift` — enriches programmes with TMDb metadata. Per uncached title: a search
    (TV only for episodic titles; otherwise movies, then TV), then one details request using
    `append_to_response` for release dates / content ratings, keywords and watch providers. A failed
    details request leaves all detail fields empty for that title.
  - `TMDbCache.swift` — actor-backed JSON cache (disposable; safe to delete/regenerate).
  - `SiteWriter.swift` — partitioned output: `channels.json` (directory, no schedules),
    `regions.json` (static `Region.all` lookup), `schedules/<date>.json` (one per day),
    `manifest.json` (generatedAt + per-file SHA-256/size).
    Deterministic encoding (sortedKeys, channels sorted by sid) so unchanged files hash identically.
    The manifest carries `generatedAt` so it is not itself hashed.
- `DTOs/`
  - `SkyServicesResponse.swift` — `services: [Service]`; `Service { sid, c (channel number), t (title),
    sf, sg (genre), xsg }` with `isAdult` (`sg == 18`), `isRadio` (`sg == 4`), and `isHD` helpers.
    Note `sf` is **uppercase** (`"HD"`/`"SD"`) in the API, so `isHD` must compare case-insensitively
    (the lowercase `== "hd"` check made every channel `isHD: false`). `sg` genres: 3 = TV,
    4 = radio, 5 = news, 6 = movies, 7 = sport, 18 = adult.
  - `SkyScheduleResponse.swift` — schedule events.

### Sky bouquet / subbouquet → region mapping

A Sky region is identified by the **(bouquet, subBouquet) pair**, not the subBouquet alone. The
bouquet encodes nation-group + resolution (4101 = England HD, 4097 = England SD, 4102/4098 = Scotland
HD/SD, 4103/4099 = England/Wales-other HD/SD, 4104/4100 = Wales/NI/Ireland/Channel Isles HD/SD). The
same region keeps the same subBouquet number across its HD and SD bouquets (e.g. London = subBouquet 1
in both 4101 and 4097). Full region table lives in `Region+all.swift` (`Region.all`), sourced from
[iptv-org/epg #1133](https://github.com/iptv-org/epg/issues/1133), and is emitted as `regions.json`.
subBouquet IDs run to 72, so the current `1...20` probe over only `Bouquet.all` captures the
England-primary HD/SD set and misses the rest — `regions.json` still lists every region for labelling,
but a channel's `regions` only contains the (bouquet, subBouquet) pairs actually fetched. The
Extra/Secondary/Tertiary bouquets (4109/4105/4110) aren't in the region table, so those pairs won't
resolve to a name.

### Sky schedule endpoint behaviour

Observed on 2026-10-05; none of this is documented by Sky.

- `/schedule/{date}/{sids}` accepts at most 20 SIDs; 21 or more returns HTTP 400 ("Invalid sid count").
  A batched response has one entry per SID, identical to the single-SID response for that SID.
- The API is HTTP/1.1 only and responses carry `Cache-Control: max-age` of up to 59 seconds.
- A date's schedule starts the previous evening (about 22:00 London time, plus whatever was already on
  air then), so consecutive day files overlap.
- **Today's date is unstable.** Two fetches a few minutes apart differ on a dozen or more channels —
  mostly programmes from the previous evening appearing or disappearing at the head of the list, plus
  the odd episode number — whether fetched singly or batched. Today's partition therefore hashes
  differently on nearly every run. When checking that a change leaves output unchanged, compare the
  later dates, and run the unchanged code twice first to see how much the data differs on its own.

## CI/CD

GitHub Actions (`.github/workflows/update-epg.yml`) runs every 12 hours:

1. `update` job — builds in `swift:6.2.0-jammy`, fetches EPG data with `--site-dir ./site`,
   auto-commits `tmdb-cache.json`, and uploads `site/` (plus `cloudflare/_headers`) as an artifact.
   The single-file `epg.json` / `epg.json.gz` output is not produced or committed by CI.
2. `deploy-pages` job — downloads the artifact and deploys it to Cloudflare Pages via
   `wrangler`. No-op until `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets are set.

## Dependencies

- `swift-argument-parser` (1.2.0+) — CLI argument parsing
- `TMDb` (18.0.1+) — The Movie Database API client (`github.com/adamayoung/TMDb`)
- `swift-crypto` (4.0.0+) — SHA-256 hashes for the partitioned manifest
