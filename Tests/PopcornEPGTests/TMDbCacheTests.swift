//
//  TMDbCacheTests.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import Testing

struct TMDbCacheTests {

    private static let day: TimeInterval = 24 * 60 * 60
    private static let foundTTL = 30 * day
    private static let notFoundTTL = 7 * day

    /// A whole-second instant, because the cache file stores ISO 8601 dates without fractional seconds.
    private static let cachedAt = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - TTL

    @Test(arguments: [
        (foundTTL - 1, true),
        (foundTTL, true),
        (foundTTL + 1, false)
    ])
    func foundEntryIsReturnedForThirtyDays(age: TimeInterval, isReturned: Bool) async {
        let cache = TMDbCache(fileURL: nil, now: { Self.cachedAt.addingTimeInterval(age) })
        await cache.set("Heat", entry: TMDbFixtures.cacheEntry(movieID: 949, cachedAt: Self.cachedAt))

        #expect(await (cache.lookup("Heat") != nil) == isReturned)
    }

    @Test(arguments: [
        (notFoundTTL - 1, true),
        (notFoundTTL, true),
        (notFoundTTL + 1, false)
    ])
    func notFoundEntryIsReturnedForSevenDays(age: TimeInterval, isReturned: Bool) async {
        let cache = TMDbCache(fileURL: nil, now: { Self.cachedAt.addingTimeInterval(age) })
        await cache.set("Local Weather", entry: TMDbFixtures.cacheEntry(cachedAt: Self.cachedAt))

        #expect(await (cache.lookup("Local Weather") != nil) == isReturned)
    }

    @Test
    func tvSeriesIDAloneCountsAsFound() async {
        let cache = TMDbCache(fileURL: nil, now: { Self.cachedAt.addingTimeInterval(8 * Self.day) })
        await cache.set("Doctor Who", entry: TMDbFixtures.cacheEntry(tvSeriesID: 57243, cachedAt: Self.cachedAt))

        #expect(await cache.lookup("Doctor Who") != nil)
    }

    // MARK: - Pruning

    @Test
    func saveRemovesExpiredEntriesAndKeepsTheRest() async throws {
        let fileURL = Self.temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let now = Self.cachedAt.addingTimeInterval(10 * Self.day)
        let cache = TMDbCache(fileURL: fileURL, now: { now })
        let freshFound = TMDbFixtures.cacheEntry(movieID: 949, cachedAt: Self.cachedAt, certification: "15")
        await cache.set("Fresh Found", entry: freshFound)
        await cache.set("Stale Not Found", entry: TMDbFixtures.cacheEntry(cachedAt: Self.cachedAt))
        await cache.set("Stale Found", entry: TMDbFixtures.cacheEntry(
            movieID: 1,
            cachedAt: now.addingTimeInterval(-31 * Self.day)
        ))
        #expect(await cache.count == 3)

        try await cache.save()

        #expect(await cache.count == 1)
        let kept = try #require(await cache.lookup("Fresh Found"))
        #expect(TMDbFields(kept) == TMDbFields(freshFound))
        #expect(kept.cachedAt == freshFound.cachedAt)
        let reloaded = TMDbCache(fileURL: fileURL, now: { now })
        #expect(await reloaded.count == 1)
    }

    @Test
    func saveWithoutFileURLIsNoOp() async throws {
        let now = Self.cachedAt.addingTimeInterval(60 * Self.day)
        let cache = TMDbCache(fileURL: nil, now: { now })
        await cache.set("Stale", entry: TMDbFixtures.cacheEntry(cachedAt: Self.cachedAt))

        try await cache.save()

        #expect(await cache.count == 1)
    }

    // MARK: - Persistence

    @Test
    func savedEntriesRoundTripThroughFile() async throws {
        let fileURL = Self.temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let now = Self.cachedAt.addingTimeInterval(Self.day)
        let entries: [String: TMDbCacheEntry] = [
            "Heat": TMDbFixtures.cacheEntry(
                movieID: 949,
                cachedAt: Self.cachedAt,
                genres: ["Action", "Crime"],
                certification: "15",
                voteAverage: 7.9,
                voteCount: 7200,
                keywords: ["heist"],
                watchProviders: ["Netflix", "ITVX"]
            ),
            "Doctor Who": TMDbFixtures.cacheEntry(
                tvSeriesID: 57243,
                cachedAt: Self.cachedAt.addingTimeInterval(-3600),
                genres: ["Drama"],
                certification: "PG",
                voteAverage: 7.5,
                voteCount: 3100,
                keywords: ["time travel"],
                watchProviders: ["BBC iPlayer"]
            ),
            "Local Weather": TMDbFixtures.cacheEntry(cachedAt: Self.cachedAt)
        ]
        let cache = TMDbCache(fileURL: fileURL, now: { now })
        for (title, entry) in entries {
            await cache.set(title, entry: entry)
        }

        try await cache.save()
        let reloaded = TMDbCache(fileURL: fileURL, now: { now })

        #expect(await reloaded.count == entries.count)
        for (title, original) in entries {
            let loaded = try #require(await reloaded.lookup(title))
            #expect(TMDbFields(loaded) == TMDbFields(original))
            #expect(loaded.cachedAt == original.cachedAt)
        }
    }

    @Test
    func loadingMissingFileGivesEmptyCache() async {
        let cache = TMDbCache(fileURL: Self.temporaryFileURL())

        #expect(await cache.count == .zero)
    }

    @Test
    func loadingMalformedFileGivesEmptyCache() async throws {
        let fileURL = Self.temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("{ \"Heat\": { \"tmdbMovieID\": \"not a number\" } ".utf8).write(to: fileURL)

        let cache = TMDbCache(fileURL: fileURL)

        #expect(await cache.count == .zero)
    }

    private static func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tmdb-cache-\(UUID().uuidString).json")
    }

}
