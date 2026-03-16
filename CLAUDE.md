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
- **Services**: `EPGService` (orchestration), `TMDbLookupService` (metadata enrichment), `TMDbCache` (JSON cache)
- **DTOs**: `SkyServicesResponse`, `SkyScheduleResponse`

## CI/CD

GitHub Actions (`.github/workflows/update-epg.yml`) runs every 12 hours, builds in `swift:6.2.0-jammy`, fetches EPG data, and auto-commits `epg.json`, `epg.json.gz`, and `tmdb-cache.json`.

## Dependencies

- `swift-argument-parser` (1.2.0+) — CLI argument parsing
- `TMDb` (17.0.0+) — The Movie Database API client (`github.com/adamayoung/TMDb`)
