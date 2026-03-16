//
//  TMDbLookupService.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
import TMDb

struct TMDbLookupService {

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

                    let entry = await lookupTitle(item.title, isTVSeries: item.isTVSeries)
                    await cache.set(item.title, entry: entry)
                    await counter.increment()
                }
            }
        }

        print("Looked up \(total) titles on TMDb.")
    }

    private func lookupTitle(_ title: String, isTVSeries: Bool) async -> TMDbCacheEntry {
        do {
            if isTVSeries {
                let results = try await tmdbClient.search.searchTVSeries(
                    query: title, filter: nil, page: nil, language: nil
                )
                if let first = results.results.first {
                    return TMDbCacheEntry(tmdbMovieID: nil, tmdbTVSeriesID: first.id, cachedAt: Date())
                }
            } else {
                let movieResults = try await tmdbClient.search.searchMovies(
                    query: title, filter: nil, page: nil, language: nil
                )
                if let first = movieResults.results.first {
                    return TMDbCacheEntry(tmdbMovieID: first.id, tmdbTVSeriesID: nil, cachedAt: Date())
                }

                let tvResults = try await tmdbClient.search.searchTVSeries(
                    query: title, filter: nil, page: nil, language: nil
                )
                if let first = tvResults.results.first {
                    return TMDbCacheEntry(tmdbMovieID: nil, tmdbTVSeriesID: first.id, cachedAt: Date())
                }
            }
        } catch {
            print("Warning: TMDb lookup failed for '\(title)': \(error)")
        }

        return TMDbCacheEntry(tmdbMovieID: nil, tmdbTVSeriesID: nil, cachedAt: Date())
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
