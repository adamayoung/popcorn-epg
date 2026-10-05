//
//  SkyMappingTests.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import Testing

struct SkyMappingTests {

    // MARK: - programmes(from:)

    @Test
    func programmeImageURLPrefersProgrammeThenSeasonThenSeriesUUID() throws {
        let events = try [
            SkyFactory.event(extraFields: ["programmeuuid": "p", "seasonuuid": "s", "seriesuuid": "r"]),
            SkyFactory.event(extraFields: ["seasonuuid": "s", "seriesuuid": "r"]),
            SkyFactory.event(extraFields: ["seriesuuid": "r"]),
            SkyFactory.event()
        ]

        let imageURLs = EPGService.programmes(from: events).map(\.imageURL)

        #expect(imageURLs == [
            "https://images.metadata.sky.com/pd-image/p/cover",
            "https://images.metadata.sky.com/pd-image/s/cover",
            "https://images.metadata.sky.com/pd-image/r/cover",
            nil
        ])
    }

    @Test
    func programmeIsPremiereFollowsNewAndDefaultsToFalse() throws {
        let events = try [
            SkyFactory.event(extraFields: ["new": true]),
            SkyFactory.event(extraFields: ["new": false]),
            SkyFactory.event()
        ]

        #expect(EPGService.programmes(from: events).map(\.isPremiere) == [true, false, false])
    }

    @Test
    func programmePassesThroughEventFields() throws {
        let event = try SkyFactory.event(
            title: "Doctor Who",
            startTime: 1_791_240_000,
            duration: 2700,
            extraFields: ["seasonnumber": 14, "episodenumber": 3, "sy": "The Doctor returns. [AD,S]"]
        )

        let programme = try #require(EPGService.programmes(from: [event]).first)

        #expect(programme.title == "Doctor Who")
        #expect(programme.startTime == 1_791_240_000)
        #expect(programme.duration == 2700)
        #expect(programme.seasonNumber == 14)
        #expect(programme.episodeNumber == 3)
        #expect(programme.description == "The Doctor returns.")
        #expect(programme.tmdbMovieID == nil)
    }

    @Test
    func programmeOptionalFieldsAreNilWhenMissing() throws {
        let programme = try #require(EPGService.programmes(from: [SkyFactory.event()]).first)

        #expect(programme.description == nil)
        #expect(programme.seasonNumber == nil)
        #expect(programme.episodeNumber == nil)
    }

    // MARK: - cleanDescription

    @Test(arguments: [
        ("[AD] A story.", "A story."),
        ("A story. [HD][S]", "A story."),
        ("A story. [S,AD]", "A story."),
        ("A story. [AD, HD]", "A story."),
        ("A story. [AD,S,HD,SL,W,BSL,3D,UHD,PG,CE]", "A story."),
        ("  A story.  ", "A story."),
        ("A story.", "A story.")
    ])
    func cleanDescriptionStripsFeatureTagsAndTrims(input: String, expected: String) {
        #expect(EPGService.cleanDescription(input) == expected)
    }

    @Test(arguments: [nil, "", "   ", "[AD]", "[HD][S]", " [S,AD] "] as [String?])
    func cleanDescriptionReturnsNilWhenNothingRemains(input: String?) {
        #expect(EPGService.cleanDescription(input) == nil)
    }

    /// Pins current behaviour: the pattern consumes whitespace on both sides of a tag.
    @Test
    func cleanDescriptionJoinsWordsAroundMidTextTag() {
        #expect(EPGService.cleanDescription("Part one [AD] part two") == "Part onepart two")
    }

    /// Pins current behaviour: the pattern also matches empty brackets.
    @Test
    func cleanDescriptionStripsEmptyBrackets() {
        #expect(EPGService.cleanDescription("A story. []") == "A story.")
    }

    /// Pins current behaviour: matching is case-sensitive and only knows the listed tags.
    @Test
    func cleanDescriptionKeepsLowercaseAndUnknownTags() {
        #expect(EPGService.cleanDescription("A story. [ad]") == "A story. [ad]")
        #expect(EPGService.cleanDescription("A story. [AD ,HD]") == "A story. [AD ,HD]")
    }

    /// Pins current behaviour: a known tag next to an unknown one is stripped along with the space before it.
    @Test
    func cleanDescriptionStripsKnownTagBesideUnknownTagAndJoinsIt() {
        #expect(EPGService.cleanDescription("A story. [AD][R]") == "A story.[R]")
    }

    /// Pins current behaviour: trimming uses `.whitespaces`, so a trailing newline not next to a tag survives.
    @Test
    func cleanDescriptionKeepsTrailingNewline() {
        #expect(EPGService.cleanDescription("A story.\n") == "A story.\n")
    }

    // MARK: - buildChannels(from:)

    private static let london = RegionRef(bouquet: 4101, subBouquet: 1)
    private static let londonSD = RegionRef(bouquet: 4097, subBouquet: 1)
    private static let essex = RegionRef(bouquet: 4101, subBouquet: 2)

    private static func service(
        sid: String = "2002",
        number: String = "101",
        name: String = "BBC One",
        format: String = "HD",
        genre: Int? = 3
    ) -> SkyServicesResponse.Service {
        SkyServicesResponse.Service(sid: sid, c: number, t: name, sf: format, sg: genre)
    }

    private func buildChannels(
        _ services: [(service: SkyServicesResponse.Service, region: RegionRef)]
    ) -> [Channel] {
        EPGService(apiClient: SkyAPIStub { _ in throw SkyAPIStub.StubError.notStubbed })
            .buildChannels(from: services)
            .sorted { $0.sid < $1.sid }
    }

    @Test
    func buildChannelsDedupesBySIDAndMergesChannelNumbers() {
        let channels = buildChannels([
            (Self.service(number: "101"), Self.london),
            (Self.service(number: "101"), Self.londonSD),
            (Self.service(number: "102"), Self.essex),
            (Self.service(sid: "2003", number: "102"), Self.london)
        ])

        #expect(channels.map(\.sid) == ["2002", "2003"])
        let numbers = channels.first?.channelNumbers ?? []
        #expect(numbers.map(\.channelNumber) == ["101", "102"])
        #expect(numbers.map(\.regions) == [[Self.londonSD, Self.london], [Self.essex]])
        #expect(channels.flatMap(\.schedules).isEmpty)
    }

    @Test
    func buildChannelsSkipsAdultServices() {
        let channels = buildChannels([
            (Self.service(sid: "2002", genre: 18), Self.london),
            (Self.service(sid: "2003", genre: 3), Self.london)
        ])

        #expect(channels.map(\.sid) == ["2003"])
    }

    @Test
    func buildChannelsDerivesTypeFromGenre() {
        let channels = buildChannels([
            (Self.service(sid: "1", genre: 4), Self.london),
            (Self.service(sid: "2", genre: 3), Self.london),
            (Self.service(sid: "3", genre: 7), Self.london),
            (Self.service(sid: "4", genre: nil), Self.london)
        ])

        #expect(channels.map(\.type) == [.radio, .tv, .tv, .tv])
    }

    @Test
    func buildChannelsIsHDMatchesFormatCaseInsensitively() {
        let channels = buildChannels([
            (Self.service(sid: "1", format: "HD"), Self.london),
            (Self.service(sid: "2", format: "hd"), Self.london),
            (Self.service(sid: "3", format: "SD"), Self.london)
        ])

        #expect(channels.map(\.isHD) == [true, true, false])
    }

    @Test
    func buildChannelsKeepsZeroPaddedNumbersDistinct() {
        let channels = buildChannels([
            (Self.service(number: "0101"), Self.london),
            (Self.service(number: "101"), Self.essex)
        ])

        let numbers = channels.first?.channelNumbers ?? []
        #expect(numbers.map(\.channelNumber) == ["0101", "101"])
        #expect(numbers.map(\.regions) == [[Self.london], [Self.essex]])
    }

    /// Pins current behaviour: channel numbers are compared as strings, so "1001" sorts before "101".
    @Test
    func buildChannelsSortsChannelNumbersLexicographically() {
        let channels = buildChannels([
            (Self.service(number: "999"), Self.london),
            (Self.service(number: "101"), Self.londonSD),
            (Self.service(number: "1001"), Self.essex)
        ])

        #expect(channels.first?.channelNumbers.map(\.channelNumber) == ["1001", "101", "999"])
    }

    @Test
    func buildChannelsSortsRegionsByBouquetThenSubBouquet() {
        let regions = [
            RegionRef(bouquet: 4101, subBouquet: 12),
            RegionRef(bouquet: 4097, subBouquet: 3),
            RegionRef(bouquet: 4101, subBouquet: 2),
            RegionRef(bouquet: 4097, subBouquet: 20)
        ]

        let channels = buildChannels(regions.map { (Self.service(), $0) })

        #expect(channels.first?.channelNumbers.first?.regions == [
            RegionRef(bouquet: 4097, subBouquet: 3),
            RegionRef(bouquet: 4097, subBouquet: 20),
            RegionRef(bouquet: 4101, subBouquet: 2),
            RegionRef(bouquet: 4101, subBouquet: 12)
        ])
    }

    @Test
    func buildChannelsSetsNameAndLogoURL() {
        let channel = buildChannels([(Self.service(sid: "2076", name: "BBC One Lon HD"), Self.london)]).first

        #expect(channel?.name == "BBC One Lon HD")
        #expect(channel?.logoURL == "https://epgstatic.sky.com/epgdata/1.0/newchanlogos/600/600/skychb2076.png")
    }

}
