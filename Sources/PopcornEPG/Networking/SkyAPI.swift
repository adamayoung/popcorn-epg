//
//  SkyAPI.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

/// The two Sky endpoints the EPG pipeline depends on, so tests can substitute canned responses.
protocol SkyAPI: Sendable {

    func fetchServices(bouquetID: Int, subbouquetID: Int) async throws -> SkyServicesResponse

    func fetchSchedule(date: String, sids: [String]) async throws -> SkyScheduleResponse

}
