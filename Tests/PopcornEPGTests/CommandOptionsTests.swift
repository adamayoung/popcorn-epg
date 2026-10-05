//
//  CommandOptionsTests.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import Testing

struct CommandOptionsTests {

    // MARK: - parseChannelNumbers

    @Test(arguments: [nil, "", " , ", ",,", "  "] as [String?])
    func parseChannelNumbersReturnsNilWhenNothingRequested(value: String?) {
        #expect(PopcornEPG.parseChannelNumbers(value) == nil)
    }

    @Test
    func parseChannelNumbersTrimsWhitespaceAroundEachNumber() {
        #expect(PopcornEPG.parseChannelNumbers("101, 106 ,301") == ["101", "106", "301"])
    }

    @Test
    func parseChannelNumbersCollapsesDuplicates() {
        #expect(PopcornEPG.parseChannelNumbers("101,101, 101") == ["101"])
    }

    @Test
    func parseChannelNumbersKeepsZeroPaddedRadioNumbersDistinct() {
        #expect(PopcornEPG.parseChannelNumbers("0101,101") == ["0101", "101"])
    }

    // MARK: - filterChannels

    private static let channels = [
        OutputFixtureBuilders.channel(sid: "3", numbers: ["301"]),
        OutputFixtureBuilders.channel(sid: "1", numbers: ["101", "801"]),
        OutputFixtureBuilders.channel(sid: "2", numbers: ["0101"], type: .radio)
    ]

    @Test
    func filterChannelsWithNilSetReturnsAllChannelsInOrder() {
        let filtered = PopcornEPG.filterChannels(Self.channels, byNumbers: nil)

        #expect(filtered.map(\.sid) == ["3", "1", "2"])
    }

    @Test
    func filterChannelsKeepsChannelsWithAnyMatchingNumberInInputOrder() {
        let filtered = PopcornEPG.filterChannels(Self.channels, byNumbers: ["801", "301"])

        #expect(filtered.map(\.sid) == ["3", "1"])
    }

    @Test
    func filterChannelsDoesNotMatchRadioNumberAgainstTVNumber() {
        let filtered = PopcornEPG.filterChannels(Self.channels, byNumbers: ["0101"])

        #expect(filtered.map(\.sid) == ["2"])
    }

    @Test
    func filterChannelsWithNoMatchReturnsEmpty() {
        #expect(PopcornEPG.filterChannels(Self.channels, byNumbers: ["999"]).isEmpty)
    }

    // MARK: - generateDates

    /// Midday UTC is at least 11 hours from midnight, so day arithmetic in the machine's
    /// Calendar.current (any UTC offset up to ±11h, including a DST hour) cannot move
    /// the instant onto a different London calendar date.
    private static func middayUTC(year: Int, month: Int, day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        return try #require(calendar.date(from: components))
    }

    @Test
    func generateDatesReturnsConsecutiveDaysFromStartDate() throws {
        let start = try Self.middayUTC(year: 2026, month: 10, day: 5)

        let dates = PopcornEPG.generateDates(count: 3, from: start)

        #expect(dates == ["20261005", "20261006", "20261007"])
    }

    @Test
    func generateDatesCrossesMonthAndYearBoundaries() throws {
        let start = try Self.middayUTC(year: 2026, month: 12, day: 30)

        let dates = PopcornEPG.generateDates(count: 4, from: start)

        #expect(dates == ["20261230", "20261231", "20270101", "20270102"])
    }

    @Test
    func generateDatesFormatsInLondonTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        // 23:30 UTC on 30 June is 00:30 BST on 1 July in London.
        let lateEvening = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 23, minute: 30))
        )

        #expect(PopcornEPG.generateDates(count: 1, from: lateEvening) == ["20260701"])
    }

    @Test
    func generateDatesWithZeroCountReturnsEmpty() throws {
        let start = try Self.middayUTC(year: 2026, month: 10, day: 5)

        #expect(PopcornEPG.generateDates(count: 0, from: start).isEmpty)
    }

}
