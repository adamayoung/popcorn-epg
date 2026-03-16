//
//  PopcornEPG.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import ArgumentParser
import Foundation

@main
struct PopcornEPG: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Fetches Sky EPG data and outputs JSON files per day."
    )

    @Option(name: .long, help: "Output JSON file path.")
    var output: String = "./epg.json"

    @Option(name: .long, help: "Number of days to fetch (today + N-1 days).")
    var days: Int = 7

    @Option(name: .long, help: "TMDb API key for metadata lookup.")
    var tmdbApiKey: String?

    @Option(name: .long, help: "Path to TMDb cache file.")
    var cache: String = "./tmdb-cache.json"

    mutating func run() async throws {
        let dates = generateDates(count: days)
        let epgService = EPGService()

        print("Fetching channels from all bouquets...")
        let channels = await epgService.fetchAllChannels()
        print("Found \(channels.count) unique channels (excluding adult).")

        print("Fetching schedules for \(days) day(s)...")
        var epgData = await epgService.fetchSchedules(for: channels, dates: dates)

        if let tmdbApiKey {
            let cacheURL = URL(fileURLWithPath: cache)
            let tmdbCache = TMDbCache(fileURL: cacheURL)
            let cacheCount = await tmdbCache.count
            print("Loaded TMDb cache (\(cacheCount) entries).")

            let lookupService = TMDbLookupService(apiKey: tmdbApiKey, cache: tmdbCache)
            epgData = await lookupService.enrichProgrammes(in: epgData)

            try await tmdbCache.save()
            let newCacheCount = await tmdbCache.count
            print("Saved TMDb cache (\(newCacheCount) entries).")
        }

        let outputURL = URL(fileURLWithPath: output)
        let outputDir = outputURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputDir.path) {
            try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(epgData)
        try atomicWrite(data, to: outputURL)
        print("Wrote \(outputURL.path) (\(epgData.channels.count) channels, \(epgData.dates.count) days)")

        let gzipURL = outputURL.appendingPathExtension("gz")
        let compressedData = try (data as NSData).compressed(using: .zlib) as Data
        try atomicWrite(compressedData, to: gzipURL)
        print("Wrote \(gzipURL.path)")

        print("Done.")
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp")
        try data.write(to: tempURL)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    private func generateDates(count: Int) -> [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "Europe/London")

        let today = Date()
        return (0 ..< count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }

            return formatter.string(from: date)
        }
    }

}
