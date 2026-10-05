//
//  SmokeTests.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import Testing

struct SmokeTests {

    @Test
    func fixturesDecode() throws {
        let batch = try Fixtures.decode(SkyScheduleResponse.self, from: Fixtures.scheduleBatch)
        #expect(batch.schedule?.count == 20)

        let services = try Fixtures.decode(SkyServicesResponse.self, from: Fixtures.services)
        #expect(services.services.count == 379)
    }

}
