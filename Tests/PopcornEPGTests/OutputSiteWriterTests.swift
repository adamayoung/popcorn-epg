//
//  OutputSiteWriterTests.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Crypto
import Foundation
@testable import PopcornEPG
import Testing

struct OutputSiteWriterTests {

    private static let generatedAt = Date(timeIntervalSince1970: 1_791_288_000)

    private static let dataFilePaths = [
        "channels.json", "regions.json", "schedules/20261005.json", "schedules/20261006.json"
    ]

    /// Two populated days (20261005, 20261006) and one empty day (20261007).
    /// Channel "2" has an empty schedule on 20261006, so it must be left out of that day's file.
    private static func sampleData(reversed: Bool = false) -> EPGData {
        let dates = ["20261006", "20261005", "20261007"]
        let channels = [
            OutputFixtureBuilders.channel(
                sid: "2",
                numbers: ["0102"],
                type: .radio,
                schedules: [
                    DaySchedule(date: "20261005", programmes: [OutputFixtureBuilders.programme(title: "Radio Show")]),
                    DaySchedule(date: "20261006", programmes: [])
                ]
            ),
            OutputFixtureBuilders.channel(
                sid: "10",
                numbers: ["106"],
                schedules: [
                    DaySchedule(date: "20261006", programmes: [OutputFixtureBuilders.programme(title: "Film")])
                ]
            ),
            OutputFixtureBuilders.channel(
                sid: "1",
                numbers: ["101"],
                schedules: [
                    DaySchedule(date: "20261005", programmes: [OutputFixtureBuilders.programme(title: "News")]),
                    DaySchedule(date: "20261006", programmes: [OutputFixtureBuilders.programme(title: "Drama")])
                ]
            )
        ]

        return EPGData(
            dates: reversed ? dates.reversed() : dates,
            channels: reversed ? channels.reversed() : channels
        )
    }

    private static func writeSite(_ data: EPGData = sampleData()) throws -> URL {
        let directory = try OutputFixtureBuilders.makeTemporaryDirectory()
        try SiteWriter(directory: directory).write(data, generatedAt: generatedAt)
        return directory
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func files(inManifest manifest: [String: Any]) throws -> [[String: Any]] {
        try #require(manifest["files"] as? [[String: Any]])
    }

    @Test
    func writesOneScheduleFilePerPopulatedDate() throws {
        let directory = try Self.writeSite()
        defer { try? FileManager.default.removeItem(at: directory) }

        let rootContents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let scheduleContents = try FileManager.default
            .contentsOfDirectory(atPath: directory.appendingPathComponent("schedules").path)

        #expect(Set(rootContents) == ["channels.json", "regions.json", "manifest.json", "schedules"])
        #expect(scheduleContents.sorted() == ["20261005.json", "20261006.json"])
    }

    @Test
    func manifestListsEveryDateButOnlyWrittenFiles() throws {
        let directory = try Self.writeSite()
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = try OutputFixtureBuilders.jsonObject(at: directory.appendingPathComponent("manifest.json"))
        let paths = try Self.files(inManifest: manifest).compactMap { $0["path"] as? String }

        #expect(manifest["dates"] as? [String] == ["20261005", "20261006", "20261007"])
        #expect(paths == Self.dataFilePaths)
        #expect(!paths.contains("manifest.json"))
    }

    @Test
    func manifestGeneratedAtIsISO8601OfGivenDate() throws {
        let directory = try Self.writeSite()
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = try OutputFixtureBuilders.jsonObject(at: directory.appendingPathComponent("manifest.json"))

        #expect(manifest["generatedAt"] as? String == "2026-10-06T12:00:00Z")
    }

    @Test
    func manifestHashesAndSizesMatchFileContents() throws {
        let directory = try Self.writeSite()
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = try OutputFixtureBuilders.jsonObject(at: directory.appendingPathComponent("manifest.json"))
        let entries = try Self.files(inManifest: manifest)
        #expect(entries.count == Self.dataFilePaths.count)

        for entry in entries {
            let path = try #require(entry["path"] as? String)
            let data = try Data(contentsOf: directory.appendingPathComponent(path))
            #expect(entry["hash"] as? String == Self.sha256Hex(data), "hash for \(path)")
            #expect(entry["bytes"] as? Int == data.count, "bytes for \(path)")
            #expect(Set(entry.keys) == ["path", "hash", "bytes"])
        }
    }

    @Test
    func channelsFileListsChannelsSortedBySIDWithoutSchedules() throws {
        let directory = try Self.writeSite()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = try OutputFixtureBuilders.jsonObject(at: directory.appendingPathComponent("channels.json"))
        let channels = try #require(file["channels"] as? [[String: Any]])

        // SIDs are strings, so "10" sorts before "2".
        #expect(channels.compactMap { $0["sid"] as? String } == ["1", "10", "2"])
        for channel in channels {
            #expect(Set(channel.keys) == ["sid", "name", "logoURL", "isHD", "type", "channelNumbers"])
        }

        let radio = try #require(channels.last)
        #expect(radio["name"] as? String == "Channel 2")
        #expect(radio["logoURL"] as? String == "https://example.com/2.png")
        #expect(radio["isHD"] as? Bool == true)
        #expect(radio["type"] as? String == "radio")
        let numbers = try #require(radio["channelNumbers"] as? [[String: Any]])
        #expect(numbers.first?["channelNumber"] as? String == "0102")
    }

    @Test
    func dayFileListsChannelsWithProgrammesSortedBySID() throws {
        let directory = try Self.writeSite()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstDay = try OutputFixtureBuilders.jsonObject(
            at: directory.appendingPathComponent("schedules/20261005.json")
        )
        let firstDayChannels = try #require(firstDay["channels"] as? [[String: Any]])
        #expect(Set(firstDay.keys) == ["date", "channels"])
        #expect(firstDay["date"] as? String == "20261005")
        #expect(firstDayChannels.compactMap { $0["sid"] as? String } == ["1", "2"])

        let secondDay = try OutputFixtureBuilders.jsonObject(
            at: directory.appendingPathComponent("schedules/20261006.json")
        )
        let secondDayChannels = try #require(secondDay["channels"] as? [[String: Any]])
        #expect(secondDayChannels.compactMap { $0["sid"] as? String } == ["1", "10"])

        for channel in firstDayChannels + secondDayChannels {
            #expect(Set(channel.keys) == ["sid", "programmes"])
        }
        let titles = secondDayChannels.compactMap { channel in
            (channel["programmes"] as? [[String: Any]])?.first?["title"] as? String
        }
        #expect(titles == ["Drama", "Film"])
    }

    @Test
    func regionsFileEqualsEncodedRegionTable() throws {
        let directory = try Self.writeSite()
        defer { try? FileManager.default.removeItem(at: directory) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let expected = try encoder.encode(RegionsFile(regions: Region.all))

        let written = try Data(contentsOf: directory.appendingPathComponent("regions.json"))

        #expect(written == expected)
    }

    @Test(arguments: [false, true])
    func writingSameDataTwiceProducesIdenticalBytes(reverseSecondInput: Bool) throws {
        let first = try Self.writeSite(Self.sampleData())
        let second = try Self.writeSite(Self.sampleData(reversed: reverseSecondInput))
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        for path in Self.dataFilePaths + ["manifest.json"] {
            let firstData = try Data(contentsOf: first.appendingPathComponent(path))
            let secondData = try Data(contentsOf: second.appendingPathComponent(path))
            #expect(firstData == secondData, "\(path) differs")
        }
    }

    @Test
    func writingTwiceIntoSameDirectoryOverwritesCleanly() throws {
        let directory = try Self.writeSite()
        defer { try? FileManager.default.removeItem(at: directory) }

        let replacement = EPGData(
            dates: ["20261005"],
            channels: [
                OutputFixtureBuilders.channel(
                    sid: "1",
                    numbers: ["101"],
                    schedules: [
                        DaySchedule(date: "20261005", programmes: [OutputFixtureBuilders.programme(title: "Late")])
                    ]
                )
            ]
        )
        try SiteWriter(directory: directory).write(replacement, generatedAt: Self.generatedAt)

        let manifest = try OutputFixtureBuilders.jsonObject(at: directory.appendingPathComponent("manifest.json"))
        #expect(manifest["dates"] as? [String] == ["20261005"])
        for entry in try Self.files(inManifest: manifest) {
            let path = try #require(entry["path"] as? String)
            let data = try Data(contentsOf: directory.appendingPathComponent(path))
            #expect(entry["hash"] as? String == Self.sha256Hex(data), "hash for \(path)")
        }

        let channels = try OutputFixtureBuilders.jsonObject(at: directory.appendingPathComponent("channels.json"))
        #expect((channels["channels"] as? [[String: Any]])?.count == 1)
        let day = try OutputFixtureBuilders.jsonObject(at: directory.appendingPathComponent("schedules/20261005.json"))
        let dayChannels = try #require(day["channels"] as? [[String: Any]])
        let title = (dayChannels.first?["programmes"] as? [[String: Any]])?.first?["title"] as? String
        #expect(title == "Late")
    }

}
