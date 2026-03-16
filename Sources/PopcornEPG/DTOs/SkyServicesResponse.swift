//
//  SkyServicesResponse.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

struct SkyServicesResponse: Decodable {

    let services: [Service]

    struct Service: Decodable {
        let sid: String
        let c: String
        let t: String
        let sf: String
        let sg: Int?

        var isAdult: Bool {
            sg == 18
        }

        var isHD: Bool {
            sf == "hd"
        }
    }

}
