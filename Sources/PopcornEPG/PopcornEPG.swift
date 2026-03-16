//
//  PopcornEPG.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import ArgumentParser
import Foundation

#if canImport(Compression)
    import Compression
#endif

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

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
        let compressedData = try compressZlib(data)
        try atomicWrite(compressedData, to: gzipURL)
        print("Wrote \(gzipURL.path)")

        print("Done.")
    }

    private func compressZlib(_ data: Data) throws -> Data {
        #if canImport(Compression)
            return try (data as NSData).compressed(using: .zlib) as Data
        #else
            let tempInput = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            let tempOutput = tempInput.appendingPathExtension("zlib")
            try data.write(to: tempInput)
            defer {
                try? FileManager.default.removeItem(at: tempInput)
                try? FileManager.default.removeItem(at: tempOutput)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", "-c", "python3 -c \"import zlib,sys; sys.stdout.buffer.write(zlib.compress(sys.stdin.buffer.read()))\" < \(tempInput.path) > \(tempOutput.path)"]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw PopcornEPGError.compressionFailed
            }

            return try Data(contentsOf: tempOutput)
        #endif
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let tempURL = url.appendingPathExtension("tmp")
        try data.write(to: tempURL)

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: url)
        }
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

enum PopcornEPGError: Error {
    case compressionFailed
}
