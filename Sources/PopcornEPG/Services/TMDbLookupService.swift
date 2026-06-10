//
//  TMDbLookupService.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
import TMDb

struct TMDbLookupService {

    /// ISO 3166-1 country code used for certifications and watch providers.
    private static let region = "GB"

    private let tmdbClient: TMDbClient
    private let cache: TMDbCache
    private let semaphore: AsyncSemaphore

    init(apiKey: String, cache: TMDbCache) {
        self.tmdbClient = TMDbClient(apiKey: apiKey)
        self.cache = cache
        self.semaphore = AsyncSemaphore(limit: 10)
    }

    func enrichProgrammes(in epgData: EPGData) async -> EPGData {
        let uniqueTitles = collectUniqueTitles(from: epgData)
        let uncachedTitles = await findUncachedTitles(uniqueTitles)

        if !uncachedTitles.isEmpty {
            await lookupUncachedTitles(uncachedTitles)
        }

        let enrichedChannels = await enrichChannels(epgData.channels)
        return EPGData(dates: epgData.dates, channels: enrichedChannels)
    }

}

// MARK: - Title Collection

extension TMDbLookupService {

    private func collectUniqueTitles(from epgData: EPGData) -> [String: Bool] {
        var uniqueTitles: [String: Bool] = [:]
        for channel in epgData.channels {
            for schedule in channel.schedules {
                for programme in schedule.programmes where uniqueTitles[programme.title] == nil {
                    let isTVSeries = programme.seasonNumber != nil || programme.episodeNumber != nil
                    uniqueTitles[programme.title] = isTVSeries
                }
            }
        }

        return uniqueTitles
    }

    private func findUncachedTitles(_ uniqueTitles: [String: Bool]) async -> [(title: String, isTVSeries: Bool)] {
        var uncachedTitles: [(title: String, isTVSeries: Bool)] = []
        for (title, isTVSeries) in uniqueTitles where await cache.lookup(title) == nil {
            uncachedTitles.append((title: title, isTVSeries: isTVSeries))
        }

        return uncachedTitles
    }

}

// MARK: - TMDb Lookup

extension TMDbLookupService {

    private func lookupUncachedTitles(_ uncachedTitles: [(title: String, isTVSeries: Bool)]) async {
        let total = uncachedTitles.count
        print("Looking up \(total) titles on TMDb...")
        let counter = ProgressCounter(total: total, interval: 100)

        await withTaskGroup(of: Void.self) { group in
            for item in uncachedTitles {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    let entry = await resolveEntry(title: item.title, isTVSeries: item.isTVSeries)
                    await cache.set(item.title, entry: entry)
                    await counter.increment()
                }
            }
        }

        print("Looked up \(total) titles on TMDb.")
    }

    /// Searches for a title's movie/TV ID and, when found, fetches its details.
    private func resolveEntry(title: String, isTVSeries: Bool) async -> TMDbCacheEntry {
        let (movieID, tvSeriesID) = await searchIDs(for: title, isTVSeries: isTVSeries)

        var details = TMDbDetails()
        if let movieID {
            details = await fetchMovieDetails(movieID, title: title)
        } else if let tvSeriesID {
            details = await fetchTVSeriesDetails(tvSeriesID, title: title)
        }

        return TMDbCacheEntry(
            tmdbMovieID: movieID,
            tmdbTVSeriesID: tvSeriesID,
            cachedAt: Date(),
            genres: details.genres,
            certification: details.certification,
            voteAverage: details.voteAverage,
            voteCount: details.voteCount,
            keywords: details.keywords,
            watchProviders: details.watchProviders
        )
    }

    /// Searches TMDb for a movie/TV ID, preserving the original resolution
    /// order: TV titles search TV only; everything else tries movies then TV.
    private func searchIDs(for title: String, isTVSeries: Bool) async -> (movieID: Int?, tvSeriesID: Int?) {
        do {
            if isTVSeries {
                let results = try await tmdbClient.search.searchTVSeries(
                    query: title, filter: nil, page: nil, language: nil
                )
                if let first = results.results.first {
                    return (nil, first.id)
                }
            } else {
                let movieResults = try await tmdbClient.search.searchMovies(
                    query: title, filter: nil, page: nil, language: nil
                )
                if let first = movieResults.results.first {
                    return (first.id, nil)
                }

                let tvResults = try await tmdbClient.search.searchTVSeries(
                    query: title, filter: nil, page: nil, language: nil
                )
                if let first = tvResults.results.first {
                    return (nil, first.id)
                }
            }
        } catch {
            print("Warning: TMDb search failed for '\(title)': \(error)")
        }

        return (nil, nil)
    }

}

// MARK: - Detail Fetching

extension TMDbLookupService {

    /// The enriched detail fields fetched from TMDb for a single title.
    private struct TMDbDetails {
        var genres: [String]?
        var certification: String?
        var voteAverage: Double?
        var voteCount: Int?
        var keywords: [String]?
        var watchProviders: [String]?
    }

    /// Fetches movie details. Each request is independent so a failure in one
    /// (e.g. keywords) still preserves whatever the others returned. Requests
    /// run sequentially to stay within the per-task semaphore budget.
    private func fetchMovieDetails(_ movieID: Int, title: String) async -> TMDbDetails {
        var details = TMDbDetails()

        do {
            let movie = try await tmdbClient.movies.details(forMovie: movieID, language: nil)
            details.genres = movie.genres?.map(\.name).nonEmptyOrNil
            details.voteAverage = movie.voteAverage
            details.voteCount = movie.voteCount
        } catch {
            print("Warning: TMDb movie details failed for '\(title)': \(error)")
        }

        do {
            let releaseDates = try await tmdbClient.movies.releaseDates(forMovie: movieID)
            details.certification = Self.gbCertification(from: releaseDates)
        } catch {
            print("Warning: TMDb movie release dates failed for '\(title)': \(error)")
        }

        do {
            let keywords = try await tmdbClient.movies.keywords(forMovie: movieID)
            details.keywords = keywords.keywords.map(\.name).nonEmptyOrNil
        } catch {
            print("Warning: TMDb movie keywords failed for '\(title)': \(error)")
        }

        do {
            let providers = try await tmdbClient.movies.watchProviders(forMovie: movieID)
            details.watchProviders = Self.gbWatchProviders(from: providers)
        } catch {
            print("Warning: TMDb movie watch providers failed for '\(title)': \(error)")
        }

        return details
    }

    /// Fetches TV series details. Mirrors `fetchMovieDetails` but uses
    /// content ratings (rather than release dates) for the GB certification.
    private func fetchTVSeriesDetails(_ tvSeriesID: Int, title: String) async -> TMDbDetails {
        var details = TMDbDetails()

        do {
            let series = try await tmdbClient.tvSeries.details(forTVSeries: tvSeriesID, language: nil)
            details.genres = series.genres?.map(\.name).nonEmptyOrNil
            details.voteAverage = series.voteAverage
            details.voteCount = series.voteCount
        } catch {
            print("Warning: TMDb TV details failed for '\(title)': \(error)")
        }

        do {
            let ratings = try await tmdbClient.tvSeries.contentRatings(forTVSeries: tvSeriesID)
            details.certification = Self.gbCertification(from: ratings)
        } catch {
            print("Warning: TMDb TV content ratings failed for '\(title)': \(error)")
        }

        do {
            let keywords = try await tmdbClient.tvSeries.keywords(forTVSeries: tvSeriesID)
            details.keywords = keywords.keywords.map(\.name).nonEmptyOrNil
        } catch {
            print("Warning: TMDb TV keywords failed for '\(title)': \(error)")
        }

        do {
            let providers = try await tmdbClient.tvSeries.watchProviders(forTVSeries: tvSeriesID)
            details.watchProviders = Self.gbWatchProviders(from: providers)
        } catch {
            print("Warning: TMDb TV watch providers failed for '\(title)': \(error)")
        }

        return details
    }

}

// MARK: - GB Field Extraction

extension TMDbLookupService {

    /// The GB/BBFC certification from a movie's release dates: the first
    /// non-empty certification among the GB country's release dates.
    private static func gbCertification(from releaseDates: [MovieReleaseDatesByCountry]) -> String? {
        guard let gbReleases = releaseDates.first(where: { $0.countryCode == region }) else {
            return nil
        }

        return gbReleases.releaseDates
            .map(\.certification)
            .first { !$0.isEmpty }
    }

    /// The GB certification from a TV series' content ratings.
    private static func gbCertification(from contentRatings: [ContentRating]) -> String? {
        guard let gbRating = contentRatings.first(where: { $0.countryCode == region }) else {
            return nil
        }

        return gbRating.rating.isEmpty ? nil : gbRating.rating
    }

    /// GB streaming provider names — flat-rate (subscription), ad-supported, and
    /// free, in that priority order, deduplicated. Buy/rent are excluded.
    private static func gbWatchProviders(from providers: [ShowWatchProvidersByCountry]) -> [String]? {
        guard let gbProviders = providers.first(where: { $0.countryCode == region }) else {
            return nil
        }

        let streaming = gbProviders.watchProviders
        let ordered = (streaming.flatRate ?? []) + (streaming.ads ?? []) + (streaming.free ?? [])

        var seen: Set<String> = []
        let names = ordered.map(\.name).filter { seen.insert($0).inserted }

        return names.nonEmptyOrNil
    }

}

// MARK: - Enrichment

extension TMDbLookupService {

    private func enrichChannels(_ channels: [Channel]) async -> [Channel] {
        var enrichedChannels: [Channel] = []
        for channel in channels {
            var enrichedChannel = channel
            var enrichedSchedules: [DaySchedule] = []
            for schedule in channel.schedules {
                let enrichedProgrammes = await enrichProgrammes(schedule.programmes)
                enrichedSchedules.append(DaySchedule(date: schedule.date, programmes: enrichedProgrammes))
            }
            enrichedChannel.schedules = enrichedSchedules
            enrichedChannels.append(enrichedChannel)
        }

        return enrichedChannels
    }

    private func enrichProgrammes(_ programmes: [Programme]) async -> [Programme] {
        var enrichedProgrammes: [Programme] = []
        for programme in programmes {
            var enrichedProgramme = programme
            if let cached = await cache.lookup(programme.title) {
                enrichedProgramme.tmdbMovieID = cached.tmdbMovieID
                enrichedProgramme.tmdbTVSeriesID = cached.tmdbTVSeriesID
                enrichedProgramme.genres = cached.genres
                enrichedProgramme.certification = cached.certification
                enrichedProgramme.voteAverage = cached.voteAverage
                enrichedProgramme.voteCount = cached.voteCount
                enrichedProgramme.keywords = cached.keywords
                enrichedProgramme.watchProviders = cached.watchProviders
            }
            enrichedProgrammes.append(enrichedProgramme)
        }

        return enrichedProgrammes
    }

}

// MARK: - ProgressCounter

private actor ProgressCounter {

    private let total: Int
    private let interval: Int
    private var count = 0

    init(total: Int, interval: Int) {
        self.total = total
        self.interval = interval
    }

    func increment() {
        count += 1
        if count % interval == 0 {
            print("TMDb lookup progress: \(count)/\(total)")
        }
    }

}

// MARK: - Helpers

private extension Array {

    /// Returns `nil` for an empty array so optional/`encodeIfPresent` fields are
    /// omitted from output rather than serialised as `[]`.
    var nonEmptyOrNil: [Element]? {
        isEmpty ? nil : self
    }

}
