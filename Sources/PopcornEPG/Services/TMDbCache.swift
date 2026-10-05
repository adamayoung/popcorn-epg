//
//  TMDbCache.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

struct TMDbCacheEntry: Codable {

    let tmdbMovieID: Int?
    let tmdbTVSeriesID: Int?
    let cachedAt: Date

    // Enriched detail fields. Optional so they're simply omitted when a title
    // doesn't resolve or a particular field is unavailable.
    var genres: [String]?
    var certification: String?
    var voteAverage: Double?
    var voteCount: Int?
    var keywords: [String]?
    var watchProviders: [String]?

    var hasResult: Bool {
        tmdbMovieID != nil || tmdbTVSeriesID != nil
    }

    func isExpired(ttl: TimeInterval, at now: Date) -> Bool {
        now.timeIntervalSince(cachedAt) > ttl
    }

}

actor TMDbCache {

    private static let defaultTTL: TimeInterval = 30 * 24 * 60 * 60
    private static let notFoundTTL: TimeInterval = 7 * 24 * 60 * 60

    private var entries: [String: TMDbCacheEntry]
    private let fileURL: URL?
    private let now: @Sendable () -> Date

    init(fileURL: URL?, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now

        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.entries = (try? decoder.decode([String: TMDbCacheEntry].self, from: data)) ?? [:]
        } else {
            self.entries = [:]
        }
    }

    var count: Int {
        entries.count
    }

    func lookup(_ title: String) -> TMDbCacheEntry? {
        guard let entry = entries[title], !isExpired(entry) else {
            return nil
        }

        return entry
    }

    func set(_ title: String, entry: TMDbCacheEntry) {
        entries[title] = entry
    }

    func save() throws {
        guard let fileURL else {
            return
        }

        // Expired entries are never returned by `lookup`, so keeping them only grows the file.
        entries = entries.filter { !isExpired($0.value) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(entries)
        try data.write(to: fileURL)
    }

    private func isExpired(_ entry: TMDbCacheEntry) -> Bool {
        entry.isExpired(ttl: entry.hasResult ? Self.defaultTTL : Self.notFoundTTL, at: now())
    }

}
