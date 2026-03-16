//
//  EPGData.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

struct EPGData: Encodable {

    let dates: [String]
    let channels: [Channel]

}
