//
//  Region+all.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

extension Region {

    /// Every known Sky region, one entry per (bouquet, subBouquet) pair — i.e.
    /// each area appears twice, once for its HD bouquet and once for its SD
    /// bouquet. Sourced from https://github.com/iptv-org/epg/issues/1133.
    ///
    /// Note: the fetcher currently only probes a subset of these (see
    /// `EPGService.maxSubbouquetID` and `Bouquet.all`), so not every region here
    /// will appear in a given channel's `regions`. The full table is published
    /// regardless so clients can label and group by any region.
    static let all: [Region] = definitions.flatMap { definition in
        let (name, nation, hdBouquet, sdBouquet, subBouquet) = definition
        return [
            Region(bouquet: hdBouquet, subBouquet: subBouquet, name: name, nation: nation, isHD: true),
            Region(bouquet: sdBouquet, subBouquet: subBouquet, name: name, nation: nation, isHD: false)
        ]
    }

    /// `(name, nation, hdBouquet, sdBouquet, subBouquet)`. Each region shares one
    /// subBouquet across its HD and SD bouquets.
    private static let definitions: [(String, String, Int, Int, Int)] = [
        // England — HD 4101 / SD 4097
        ("London", "England", 4101, 4097, 1),
        ("Essex", "England", 4101, 4097, 2),
        ("Central Midlands", "England", 4101, 4097, 3),
        ("HTV West", "England", 4101, 4097, 4),
        ("Meridian South", "England", 4101, 4097, 5),
        ("Westcountry", "England", 4101, 4097, 6),
        ("Granada", "England", 4101, 4097, 7),
        ("North West Yorkshire", "England", 4101, 4097, 8),
        ("Thames Valley", "England", 4101, 4097, 9),
        ("Meridian South East", "England", 4101, 4097, 10),
        ("Meridian East", "England", 4101, 4097, 11),
        ("Border England", "England", 4101, 4097, 12),
        ("Tyne", "England", 4101, 4097, 13),
        ("London / Essex", "England", 4101, 4097, 18),
        ("Atherstone", "England", 4101, 4097, 19),
        ("East Midlands", "England", 4101, 4097, 20),
        ("Norfolk", "England", 4101, 4097, 21),
        ("Gloucester", "England", 4101, 4097, 24),
        ("West Anglia", "England", 4101, 4097, 25),
        ("North Yorkshire", "England", 4101, 4097, 26),
        ("Tring", "England", 4101, 4097, 27),
        ("South Lakeland", "England", 4101, 4097, 28),
        ("Humber", "England", 4101, 4097, 29),

        // Scotland — HD 4102 / SD 4098
        ("Grampian", "Scotland", 4102, 4098, 35),
        ("Border Scotland", "Scotland", 4102, 4098, 36),
        ("Scottish West", "Scotland", 4102, 4098, 37),
        ("Scottish East", "Scotland", 4102, 4098, 38),
        ("Dundee", "Scotland", 4102, 4098, 39),

        // England & Wales (other) — HD 4103 / SD 4099
        ("Ridge Hill", "England", 4103, 4099, 41),
        ("HTV Wales", "Wales", 4103, 4099, 43),
        ("Merseyside", "England", 4103, 4099, 45),
        ("Sheffield", "England", 4103, 4099, 60),
        ("Scarborough", "England", 4103, 4099, 61),
        ("North East Midlands", "England", 4103, 4099, 62),
        ("HTV West / Thames Valley", "England", 4103, 4099, 63),
        ("London Kent", "England", 4103, 4099, 64),
        ("Brighton", "England", 4103, 4099, 65),
        ("London / Thames Valley", "England", 4103, 4099, 66),
        ("West Dorset", "England", 4103, 4099, 67),
        ("Meridian North", "England", 4103, 4099, 68),
        ("Tees", "England", 4103, 4099, 69),
        ("Henley On Thames", "England", 4103, 4099, 70),
        ("Oxford", "England", 4103, 4099, 71),
        ("South Yorkshire", "England", 4103, 4099, 72),

        // Wales, Northern Ireland, Ireland, Channel Islands — HD 4104 / SD 4100
        ("Wales", "Wales", 4104, 4100, 32),
        ("Northern Ireland", "Northern Ireland", 4104, 4100, 33),
        ("Channel Isles", "Channel Islands", 4104, 4100, 34),
        ("Republic of Ireland", "Ireland", 4104, 4100, 50)
    ]

}
