//
//  Fixtures.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

/// Real Sky API responses captured on 2026-10-05, in `Fixtures/`.
enum Fixtures {

    /// `/schedule/20261006/<20 SIDs>` — one batched request for the first 20 channels.
    static let scheduleBatch = "sky-schedule-20261006-batch.json"

    /// `/schedule/20261006/1003` — the single-SID request for the first channel in the batch.
    static let scheduleSID1003 = "sky-schedule-20261006-sid-1003.json"

    /// `/services/4101/1` — Sky Default bouquet, London.
    static let services = "sky-services-4101-1.json"

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }

        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(name))
    }

    enum FixtureError: Error {
        case missing(String)
    }

}
