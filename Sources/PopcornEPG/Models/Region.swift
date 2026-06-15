//
//  Region.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

/// A Sky EPG region. A region is identified by the **(bouquet, subBouquet)
/// pair** — the bouquet encodes the nation-group and resolution, the subBouquet
/// the area within it. The same area keeps the same `subBouquet` across its HD
/// and SD bouquets (e.g. London is subBouquet 1 in both 4101 HD and 4097 SD).
///
/// Channel numbers in the output are keyed by this pair (see `RegionRef` on
/// `ChannelNumberMapping`), so a client can join a channel's number to a region
/// name and filter the guide by bouquet and subBouquet.
struct Region: Encodable {

    let bouquet: Int
    let subBouquet: Int
    let name: String
    let nation: String
    let isHD: Bool

}

/// Wrapper for the standalone `regions.json` output file.
struct RegionsFile: Encodable {

    let regions: [Region]

}
