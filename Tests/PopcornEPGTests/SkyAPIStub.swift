//
//  SkyAPIStub.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG

/// A `SkyAPI` that records every request and answers schedule requests from a closure.
final class SkyAPIStub: SkyAPI, @unchecked Sendable {

    struct ScheduleRequest: Hashable, CustomStringConvertible {
        let date: String
        let sids: [String]

        var description: String {
            "\(date)/\(sids.joined(separator: ","))"
        }
    }

    enum StubError: Error {
        case failed
        case notStubbed
    }

    typealias ScheduleHandler = @Sendable (ScheduleRequest) throws -> SkyScheduleResponse

    private let lock = NSLock()
    private let scheduleHandler: ScheduleHandler
    private var recordedScheduleRequests: [ScheduleRequest] = []

    init(schedule scheduleHandler: @escaping ScheduleHandler) {
        self.scheduleHandler = scheduleHandler
    }

    var scheduleRequests: [ScheduleRequest] {
        lock.withLock { recordedScheduleRequests }
    }

    func fetchServices(bouquetID _: Int, subbouquetID _: Int) async throws -> SkyServicesResponse {
        throw StubError.notStubbed
    }

    func fetchSchedule(date: String, sids: [String]) async throws -> SkyScheduleResponse {
        let request = ScheduleRequest(date: date, sids: sids)
        lock.withLock { recordedScheduleRequests.append(request) }
        return try scheduleHandler(request)
    }

}

/// Builders for Sky DTOs and models, so tests can describe inputs tersely.
enum SkyFactory {

    static func channel(sid: String) -> Channel {
        Channel(
            sid: sid,
            name: "Channel \(sid)",
            logoURL: "",
            isHD: false,
            type: .tv,
            channelNumbers: [],
            schedules: []
        )
    }

    static func channels(count: Int) -> [Channel] {
        (1 ... count).map { channel(sid: String(1000 + $0)) }
    }

    /// `Event` has only a decoding initialiser, so events are built from JSON.
    static func event(
        title: String = "Programme",
        startTime: Int = 1_791_233_100,
        duration: Int = 1800,
        extraFields: [String: Any] = [:]
    ) throws -> SkyScheduleResponse.Event {
        var fields: [String: Any] = ["t": title, "st": startTime, "d": duration]
        fields.merge(extraFields) { _, extra in extra }
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(SkyScheduleResponse.Event.self, from: data)
    }

    static func entry(sid: String, titles: [String]) throws -> SkyScheduleResponse.ScheduleEntry {
        try SkyScheduleResponse.ScheduleEntry(sid: sid, events: titles.map { try event(title: $0) })
    }

    static func response(_ entries: [SkyScheduleResponse.ScheduleEntry]) -> SkyScheduleResponse {
        SkyScheduleResponse(schedule: entries)
    }

    /// A response giving each requested SID one programme titled `"<sid> on <date>"`.
    static func echoResponse(for request: SkyAPIStub.ScheduleRequest) throws -> SkyScheduleResponse {
        try response(request.sids.map { try entry(sid: $0, titles: ["\($0) on \(request.date)"]) })
    }

}
