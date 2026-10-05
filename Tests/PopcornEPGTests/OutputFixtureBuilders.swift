//
//  OutputFixtureBuilders.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import Testing

enum OutputFixtureBuilders {

    static func programme(title: String = "News", startTime: Int = 1_791_288_000) -> Programme {
        Programme(
            title: title,
            description: nil,
            startTime: startTime,
            duration: 1800,
            seasonNumber: nil,
            episodeNumber: nil,
            isPremiere: false,
            imageURL: nil
        )
    }

    static func channel(
        sid: String,
        name: String? = nil,
        numbers: [String] = [],
        type: ChannelType = .tv,
        schedules: [DaySchedule] = []
    ) -> Channel {
        Channel(
            sid: sid,
            name: name ?? "Channel \(sid)",
            logoURL: "https://example.com/\(sid).png",
            isHD: true,
            type: type,
            channelNumbers: numbers.map { number in
                ChannelNumberMapping(
                    channelNumber: number,
                    regions: [RegionRef(bouquet: 4101, subBouquet: 1)]
                )
            },
            schedules: schedules
        )
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopcornEPGTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

}
