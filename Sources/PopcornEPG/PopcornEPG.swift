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

    @Option(name: .long, help: "Single-file JSON output path (also writes a .gz). Omit to skip single-file output.")
    var output: String?

    @Option(name: .long, help: "Number of days to fetch (today + N-1 days).")
    var days: Int = 7

    @Option(name: .long, help: "TMDb API key for metadata lookup.")
    var tmdbApiKey: String?

    @Option(name: .long, help: "Path to TMDb cache file.")
    var cache: String = "./tmdb-cache.json"

    @Option(
        name: .long,
        help: "Comma-separated channel numbers to fetch (e.g. 101,106,301). Omit to fetch all channels."
    )
    var channels: String?

    @Option(
        name: .long,
        help: "Directory for partitioned site files (manifest.json, channels.json, schedules/). Omit to skip."
    )
    var siteDir: String?

    mutating func run() async throws {
        let dates = generateDates(count: days)
        let epgService = EPGService()

        print("Fetching channels from all bouquets...")
        let allChannels = await epgService.fetchAllChannels()
        print("Found \(allChannels.count) unique channels (excluding adult).")

        let requestedNumbers = parseChannelNumbers(channels)
        let selectedChannels = filterChannels(allChannels, byNumbers: requestedNumbers)
        if let requestedNumbers {
            let list = requestedNumbers.sorted().joined(separator: ", ")
            print("Filtered to \(selectedChannels.count) channel(s) matching: \(list).")
        }

        print("Fetching schedules for \(days) day(s)...")
        var epgData = await epgService.fetchSchedules(for: selectedChannels, dates: dates)

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

        if let output {
            try writeSingleFile(epgData, to: output)
        }

        if let siteDir {
            let siteURL = URL(fileURLWithPath: siteDir)
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: siteURL, withIntermediateDirectories: true)
            try SiteWriter(directory: siteURL).write(epgData)
            print("Wrote partitioned site to \(siteURL.path) (\(epgData.dates.count) day file(s) + manifest).")
        }

        print("Done.")
    }

    /// Writes the single-file JSON guide (`epg.json`), its zlib `.gz`, and the
    /// static `regions.json` lookup, all into the directory of `output`.
    private func writeSingleFile(_ epgData: EPGData, to output: String) throws {
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

        // Static region lookup alongside the guide, for clients that resolve a
        // channel's (bouquet, subBouquet) pairs to region names.
        let regionsURL = outputDir.appendingPathComponent("regions.json")
        let regionsData = try encoder.encode(RegionsFile(regions: Region.all))
        try atomicWrite(regionsData, to: regionsURL)
        print("Wrote \(regionsURL.path) (\(Region.all.count) regions)")
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
            process.arguments = [
                "bash",
                "-c",
                "python3 -c \"import zlib,sys; sys.stdout.buffer.write(zlib.compress(sys.stdin.buffer.read()))\" < \(tempInput.path) > \(tempOutput.path)"
            ]
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
        try? fileManager.removeItem(at: url)
        try fileManager.moveItem(at: tempURL, to: url)
    }

    /// Parses the `--channels` value into a set of channel numbers, or `nil`
    /// when the option is absent/empty (meaning "all channels").
    private func parseChannelNumbers(_ value: String?) -> Set<String>? {
        guard let value else {
            return nil
        }

        let numbers = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return numbers.isEmpty ? nil : Set(numbers)
    }

    /// Keeps only channels exposing one of the requested channel numbers.
    /// Returns all channels when no filter is supplied.
    private func filterChannels(_ channels: [Channel], byNumbers numbers: Set<String>?) -> [Channel] {
        guard let numbers else {
            return channels
        }

        return channels.filter { channel in
            channel.channelNumbers.contains { numbers.contains($0.channelNumber) }
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
