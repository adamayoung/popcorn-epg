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
    let regions: [RegionRef]

}

/// A reference to the Sky region — the (bouquet, subBouquet) pair — under which a
/// channel carries a given channel number. Join to `Region` (see `regions.json`)
/// to resolve the human-readable region name.
struct RegionRef: Encodable, Hashable {

    let bouquet: Int
    let subBouquet: Int

}

struct DaySchedule: Encodable {

    let date: String
    var programmes: [Programme]

}
