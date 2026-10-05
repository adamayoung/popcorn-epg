//
//  EPGServiceScheduleTests.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import Testing

struct EPGServiceScheduleTests {

    private typealias Request = SkyAPIStub.ScheduleRequest

    // MARK: - Batching

    @Test
    func scheduleRequestBatchesSplitsIntoGroupsOfTwenty() {
        let batches = EPGService.scheduleRequestBatches(of: SkyFactory.channels(count: 45))

        #expect(batches.map(\.count) == [20, 20, 5])
        #expect(batches.flatMap(\.self).map(\.sid) == SkyFactory.channels(count: 45).map(\.sid))
    }

    @Test
    func fortyFiveChannelsAreRequestedAsThreeBatchesOncePerDate() async {
        let channels = SkyFactory.channels(count: 45)
        let stub = SkyAPIStub(schedule: SkyFactory.echoResponse)

        _ = await EPGService(apiClient: stub).fetchSchedules(for: channels, dates: ["20261006", "20261007"])

        let sids = channels.map(\.sid)
        let expectedBatches = [Array(sids[0 ..< 20]), Array(sids[20 ..< 40]), Array(sids[40 ..< 45])]
        for date in ["20261006", "20261007"] {
            let requestsForDate = stub.scheduleRequests.filter { $0.date == date }
            #expect(requestsForDate.count == 3)
            #expect(Set(requestsForDate) == Set(expectedBatches.map { Request(date: date, sids: $0) }))
        }
        #expect(stub.scheduleRequests.count == 6)
    }

    @Test
    func everyChannelInEveryBatchGetsItsProgrammes() async throws {
        let channels = SkyFactory.channels(count: 45)
        let stub = SkyAPIStub(schedule: SkyFactory.echoResponse)

        let epg = await EPGService(apiClient: stub).fetchSchedules(for: channels, dates: ["20261006"])

        #expect(epg.channels.map(\.sid) == channels.map(\.sid))
        let last = try #require(epg.channels.last)
        #expect(last.schedules.first?.programmes.map(\.title) == ["1045 on 20261006"])
    }

    // MARK: - Matching by SID

    @Test
    func entriesAreMatchedBySIDNotPosition() async {
        let stub = SkyAPIStub { _ in
            try SkyFactory.response([
                SkyFactory.entry(sid: "C", titles: ["C show"]),
                SkyFactory.entry(sid: "A", titles: ["A show"]),
                SkyFactory.entry(sid: "B", titles: ["B show"])
            ])
        }

        let epg = await EPGService(apiClient: stub)
            .fetchSchedules(for: ["A", "B", "C"].map(SkyFactory.channel), dates: ["20261006"])

        #expect(epg.channels.map(\.sid) == ["A", "B", "C"])
        #expect(epg.channels.map { $0.schedules.first?.programmes.first?.title } == ["A show", "B show", "C show"])
    }

    @Test
    func absentNullAndEmptyEventsGiveNoProgrammesForThatDate() async {
        let stub = SkyAPIStub { _ in
            try SkyFactory.response([
                SkyFactory.entry(sid: "A", titles: ["A show"]),
                SkyScheduleResponse.ScheduleEntry(sid: "NULL", events: nil),
                SkyScheduleResponse.ScheduleEntry(sid: "EMPTY", events: [])
            ])
        }

        let epg = await EPGService(apiClient: stub)
            .fetchSchedules(for: ["A", "ABSENT", "NULL", "EMPTY"].map(SkyFactory.channel), dates: ["20261006"])

        #expect(epg.channels.map(\.sid) == ["A"])
    }

    @Test
    func duplicateSIDInResponseKeepsFirstEntry() async {
        let stub = SkyAPIStub { _ in
            try SkyFactory.response([
                SkyFactory.entry(sid: "A", titles: ["first"]),
                SkyFactory.entry(sid: "B", titles: ["B show"]),
                SkyFactory.entry(sid: "A", titles: ["second"])
            ])
        }

        let epg = await EPGService(apiClient: stub)
            .fetchSchedules(for: ["A", "B"].map(SkyFactory.channel), dates: ["20261006"])

        #expect(epg.channels.first?.schedules.first?.programmes.map(\.title) == ["first"])
    }

    @Test
    func eventsBySIDKeepsFirstEntryAndTreatsNullEventsAsEmpty() throws {
        let response = try SkyFactory.response([
            SkyFactory.entry(sid: "A", titles: ["first"]),
            SkyScheduleResponse.ScheduleEntry(sid: "B", events: nil),
            SkyFactory.entry(sid: "A", titles: ["second"])
        ])

        let eventsBySID = EPGService.eventsBySID(in: response)

        #expect(eventsBySID["A"]?.map(\.t) == ["first"])
        #expect(eventsBySID["B"]?.isEmpty == true)
        #expect(EPGService.eventsBySID(in: SkyScheduleResponse(schedule: nil)).isEmpty)
    }

    // MARK: - Fallback

    @Test
    func failedBatchFallsBackToSingleSIDRequestsInOrder() async {
        let stub = SkyAPIStub { request in
            if request.sids.count > 1 || request.sids == ["B"] {
                throw SkyAPIStub.StubError.failed
            }
            return try SkyFactory.echoResponse(for: request)
        }

        let epg = await EPGService(apiClient: stub)
            .fetchSchedules(for: ["A", "B", "C"].map(SkyFactory.channel), dates: ["20261006"])

        #expect(stub.scheduleRequests == [
            Request(date: "20261006", sids: ["A", "B", "C"]),
            Request(date: "20261006", sids: ["A"]),
            Request(date: "20261006", sids: ["B"]),
            Request(date: "20261006", sids: ["C"])
        ])
        #expect(epg.channels.map(\.sid) == ["A", "C"])
        #expect(epg.channels.map { $0.schedules.first?.programmes.first?.title } == [
            "A on 20261006", "C on 20261006"
        ])
    }

    @Test
    func failedBatchOnOneDateOnlyLosesThatDateWhenSingleRequestsAlsoFail() async {
        let stub = SkyAPIStub { request in
            if request.date == "20261007" {
                throw SkyAPIStub.StubError.failed
            }
            return try SkyFactory.echoResponse(for: request)
        }

        let epg = await EPGService(apiClient: stub)
            .fetchSchedules(for: ["A", "B"].map(SkyFactory.channel), dates: ["20261006", "20261007"])

        #expect(epg.channels.map { $0.schedules.map(\.date) } == [["20261006"], ["20261006"]])
        #expect(stub.scheduleRequests.filter { $0.date == "20261007" }.map(\.sids) == [["A", "B"], ["A"], ["B"]])
    }

    @Test
    func singleChannelBatchMakesOneRequest() async {
        let stub = SkyAPIStub(schedule: SkyFactory.echoResponse)

        let epg = await EPGService(apiClient: stub).fetchSchedules(
            for: [SkyFactory.channel(sid: "A")],
            dates: ["20261006"]
        )

        #expect(stub.scheduleRequests == [Request(date: "20261006", sids: ["A"])])
        #expect(epg.channels.map(\.sid) == ["A"])
    }

    @Test
    func failedSingleChannelBatchIsNotRetried() async {
        let stub = SkyAPIStub { _ in throw SkyAPIStub.StubError.failed }

        let epg = await EPGService(apiClient: stub).fetchSchedules(
            for: [SkyFactory.channel(sid: "A")],
            dates: ["20261006"]
        )

        #expect(stub.scheduleRequests == [Request(date: "20261006", sids: ["A"])])
        #expect(epg.channels.isEmpty)
    }

    @Test
    func trailingSingleChannelBatchOfTwentyOneMakesOneRequestForIt() async {
        let channels = SkyFactory.channels(count: 21)
        let stub = SkyAPIStub(schedule: SkyFactory.echoResponse)

        _ = await EPGService(apiClient: stub).fetchSchedules(for: channels, dates: ["20261006"])

        #expect(stub.scheduleRequests.count == 2)
        #expect(stub.scheduleRequests.contains(Request(date: "20261006", sids: ["1021"])))
    }

    /// Pins current behaviour: a single-SID request reads the response's first entry without checking its SID.
    @Test
    func singleSIDRequestUsesFirstEntryEvenWhenItsSIDDiffers() async {
        let stub = SkyAPIStub { _ in
            try SkyFactory.response([SkyFactory.entry(sid: "OTHER", titles: ["other show"])])
        }

        let epg = await EPGService(apiClient: stub).fetchSchedules(
            for: [SkyFactory.channel(sid: "A")],
            dates: ["20261006"]
        )

        #expect(epg.channels.first?.schedules.first?.programmes.map(\.title) == ["other show"])
    }

    // MARK: - Assembly

    @Test
    func channelsWithoutProgrammesAreDroppedAndPartialDaysKept() async throws {
        let dates = ["20261006", "20261007", "20261008"]
        let stub = SkyAPIStub { request in
            let sids = request.sids.filter { sid in
                switch sid {
                case "BOTH": request.date != "20261007"
                case "LAST": request.date == "20261008"
                default: false
                }
            }
            return try SkyFactory.echoResponse(for: SkyAPIStub.ScheduleRequest(date: request.date, sids: sids))
        }

        let epg = await EPGService(apiClient: stub)
            .fetchSchedules(for: ["NONE", "BOTH", "LAST"].map(SkyFactory.channel), dates: dates)

        #expect(epg.dates == dates)
        #expect(epg.channels.map(\.sid) == ["BOTH", "LAST"])
        let both = try #require(epg.channels.first)
        #expect(both.schedules.map(\.date) == ["20261006", "20261008"])
        #expect(both.schedules.map { $0.programmes.map(\.title) } == [["BOTH on 20261006"], ["BOTH on 20261008"]])
        #expect(epg.channels.last?.schedules.map(\.date) == ["20261008"])
    }

}
