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

    var hasResult: Bool {
        tmdbMovieID != nil || tmdbTVSeriesID != nil
    }

    func isExpired(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(cachedAt) > ttl
    }

}

actor TMDbCache {

    private static let defaultTTL: TimeInterval = 30 * 24 * 60 * 60
    private static let notFoundTTL: TimeInterval = 7 * 24 * 60 * 60

    private var entries: [String: TMDbCacheEntry]
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL

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
        guard let entry = entries[title] else {
            return nil
        }

        let ttl = entry.hasResult ? Self.defaultTTL : Self.notFoundTTL
        if entry.isExpired(ttl: ttl) {
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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(entries)
        try data.write(to: fileURL)
    }

}
