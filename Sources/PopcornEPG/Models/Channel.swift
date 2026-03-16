//
//  Channel.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

struct Channel: Encodable {

    let sid: String
    let name: String
    let logoURL: String
    let isHD: Bool
    var channelNumbers: [ChannelNumberMapping]
    var schedules: [DaySchedule]

}

struct ChannelNumberMapping: Encodable {

    let channelNumber: String
    let subbouquetIDs: [Int]

}

struct DaySchedule: Encodable {

    let date: String
    var programmes: [Programme]

}
