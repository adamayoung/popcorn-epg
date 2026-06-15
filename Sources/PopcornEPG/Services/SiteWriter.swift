//
//  SiteWriter.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Crypto
import Foundation

/// Writes the EPG as a set of small, independently-cacheable files for a static
/// host (e.g. Cloudflare Pages). Clients sync incrementally: fetch
/// `manifest.json`, compare the per-file SHA-256 hashes against their local
/// copy, and download only the partitions that changed.
///
///     <dir>/manifest.json          — index: generatedAt + hash/size per file
///     <dir>/channels.json          — channel directory (no schedules)
///     <dir>/schedules/<date>.json  — one file per day
///
/// All data files are encoded deterministically (sorted keys, channels sorted by
/// SID), so an unchanged day produces a byte-identical file — and therefore an
/// identical hash — across runs, letting clients (and the CDN) skip it.
struct SiteWriter {

    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func write(_ epgData: EPGData, generatedAt: Date = Date()) throws {
        let schedulesDirectory = directory.appendingPathComponent("schedules", isDirectory: true)
        try fileManager.createDirectory(at: schedulesDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let channels = epgData.channels.sorted { $0.sid < $1.sid }
        var entries: [ManifestEntry] = []

        let channelsFile = ChannelsFile(channels: channels.map(ChannelInfo.init))
        try entries.append(writeFile(channelsFile, to: "channels.json", using: encoder))

        // Static region lookup, so clients can resolve a channel's (bouquet,
        // subBouquet) pairs to region names and filter the guide by region.
        let regionsFile = RegionsFile(regions: Region.all)
        try entries.append(writeFile(regionsFile, to: "regions.json", using: encoder))

        for date in epgData.dates.sorted() {
            let dayChannels = channels.compactMap { channel -> DayChannel? in
                guard let schedule = channel.schedules.first(where: { $0.date == date }),
                      !schedule.programmes.isEmpty
                else {
                    return nil
                }

                return DayChannel(sid: channel.sid, programmes: schedule.programmes)
            }

            guard !dayChannels.isEmpty else {
                continue
            }

            let dayFile = DayScheduleFile(date: date, channels: dayChannels)
            try entries.append(writeFile(dayFile, to: "schedules/\(date).json", using: encoder))
        }

        let manifest = Manifest(
            generatedAt: ISO8601DateFormatter().string(from: generatedAt),
            dates: epgData.dates.sorted(),
            files: entries.sorted { $0.path < $1.path }
        )

        // The manifest carries `generatedAt`, so it changes every run and is not
        // itself hashed; clients always fetch it first to learn what changed.
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: directory.appendingPathComponent("manifest.json"))
    }

    private func writeFile(
        _ value: some Encodable,
        to relativePath: String,
        using encoder: JSONEncoder
    ) throws -> ManifestEntry {
        let data = try encoder.encode(value)
        try data.write(to: directory.appendingPathComponent(relativePath))

        return ManifestEntry(path: relativePath, hash: Self.sha256Hex(of: data), bytes: data.count)
    }

    private static func sha256Hex(of data: Data) -> String {
        let digits = Array("0123456789abcdef")
        return SHA256.hash(data: data).reduce(into: "") { result, byte in
            result.append(digits[Int(byte >> 4)])
            result.append(digits[Int(byte & 0x0F)])
        }
    }

}

// MARK: - File Models

private struct Manifest: Encodable {
    let generatedAt: String
    let dates: [String]
    let files: [ManifestEntry]
}

private struct ManifestEntry: Encodable {
    let path: String
    let hash: String
    let bytes: Int
}

private struct ChannelsFile: Encodable {
    let channels: [ChannelInfo]
}

private struct ChannelInfo: Encodable {
    let sid: String
    let name: String
    let logoURL: String
    let isHD: Bool
    let channelNumbers: [ChannelNumberMapping]

    init(_ channel: Channel) {
        self.sid = channel.sid
        self.name = channel.name
        self.logoURL = channel.logoURL
        self.isHD = channel.isHD
        self.channelNumbers = channel.channelNumbers
    }
}

private struct DayScheduleFile: Encodable {
    let date: String
    let channels: [DayChannel]
}

private struct DayChannel: Encodable {
    let sid: String
    let programmes: [Programme]
}
