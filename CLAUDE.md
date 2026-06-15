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
- **Networking**: `SkyAPIClient` with retry/backoff, `AsyncSemaphore` limiting to 20 concurrent requests
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
  - `Channel.swift` — `Channel` (sid, name, logoURL, isHD, `channelNumbers: [ChannelNumberMapping]`,
    `schedules: [DaySchedule]`), `ChannelNumberMapping` (channelNumber, `regions: [RegionRef]`),
    `RegionRef` (`bouquet`, `subBouquet`; `Hashable`), `DaySchedule` (date, programmes). All `Encodable`.
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
    → `/services/{b}/{s}`; `fetchSchedule(date:sid:)` → `/schedule/{date}/{sid}`. 3 retries, exponential
    backoff, retries on 429/500/502/503/504.
  - `SkyAPIError.swift` — `invalidURL`, `httpError(statusCode:)`, `decodingError`.
- `Services/`
  - `EPGService.swift` — orchestration. `fetchAllServices()` probes every `Bouquet.all` × subbouquet
    `1...20` (`maxSubbouquetID`) in a task group, swallowing failures, tagging each service with a
    `RegionRef(bouquet, subBouquet)`. `buildChannels()` dedupes by `service.sid`, skips adult
    (`sg == 18`), and groups channel numbers → the `RegionRef`s they appear in (bouquet + subbouquet
    both preserved). `fetchAllSchedules()` fans out per channel/date under a 20-permit
    `AsyncSemaphore`. `cleanDescription` strips `[AD][HD][S]…` feature tags via regex.
  - `TMDbLookupService.swift` — enriches programmes with TMDb metadata.
  - `TMDbCache.swift` — actor-backed JSON cache (disposable; safe to delete/regenerate).
  - `SiteWriter.swift` — partitioned output: `channels.json` (directory, no schedules),
    `regions.json` (static `Region.all` lookup), `schedules/<date>.json` (one per day),
    `manifest.json` (generatedAt + per-file SHA-256/size).
    Deterministic encoding (sortedKeys, channels sorted by sid) so unchanged files hash identically.
    The manifest carries `generatedAt` so it is not itself hashed.
- `DTOs/`
  - `SkyServicesResponse.swift` — `services: [Service]`; `Service { sid, c (channel number), t (title),
    sf (hd/sd), sg (genre; 18 = adult) }` with `isAdult`/`isHD` helpers.
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

## CI/CD

GitHub Actions (`.github/workflows/update-epg.yml`) runs every 12 hours:

1. `update` job — builds in `swift:6.2.0-jammy`, fetches EPG data with `--site-dir ./site`,
   auto-commits `epg.json`, `epg.json.gz`, and `tmdb-cache.json`, and uploads `site/` (plus
   `cloudflare/_headers`) as an artifact.
2. `deploy-pages` job — downloads the artifact and deploys it to Cloudflare Pages via
   `wrangler`. No-op until `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets are set.

## Dependencies

- `swift-argument-parser` (1.2.0+) — CLI argument parsing
- `TMDb` (18.0.1+) — The Movie Database API client (`github.com/adamayoung/TMDb`)
- `swift-crypto` (4.0.0+) — SHA-256 hashes for the partitioned manifest
