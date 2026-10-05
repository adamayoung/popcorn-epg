//
//  OutputProgrammeEncodingTests.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import Testing

struct OutputProgrammeEncodingTests {

    private static func fullyPopulatedProgramme() -> Programme {
        var programme = Programme(
            title: "Inception",
            description: "A thief steals secrets through dreams.",
            startTime: 1_791_288_000,
            duration: 9000,
            seasonNumber: 2,
            episodeNumber: 5,
            isPremiere: true,
            imageURL: "https://example.com/inception.jpg"
        )
        programme.tmdbMovieID = 27205
        programme.tmdbTVSeriesID = 1399
        programme.genres = ["Action", "Science Fiction"]
        programme.certification = "12A"
        programme.voteAverage = 8.5
        programme.voteCount = 37000
        programme.keywords = ["dream", "heist"]
        programme.watchProviders = ["Sky Go", "NOW"]
        return programme
    }

    private static func encode(_ programme: Programme) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(programme)
        return try #require(String(data: data, encoding: .utf8))
    }

    private static func keys(of programme: Programme) throws -> Set<String> {
        let json = try encode(programme)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let dictionary = try #require(object as? [String: Any])
        return Set(dictionary.keys)
    }

    @Test
    func minimalProgrammeOmitsNilOptionalsAndFalsePremiere() throws {
        let json = try Self.encode(OutputFixtureBuilders.programme(title: "News", startTime: 100))

        #expect(json == #"{"duration":1800,"startTime":100,"title":"News"}"#)
        #expect(!json.contains("null"))
    }

    @Test
    func isPremiereEncodedAsTrueWhenSet() throws {
        let programme = Programme(
            title: "Premiere",
            description: nil,
            startTime: 100,
            duration: 60,
            seasonNumber: nil,
            episodeNumber: nil,
            isPremiere: true,
            imageURL: nil
        )

        let json = try Self.encode(programme)

        #expect(json.contains(#""isPremiere":true"#))
    }

    @Test
    func everyNonNilFieldIsPresentUnderItsKey() throws {
        let keys = try Self.keys(of: Self.fullyPopulatedProgramme())

        #expect(keys == [
            "title", "description", "startTime", "duration", "seasonNumber", "episodeNumber", "isPremiere",
            "imageURL", "tmdbMovieID", "tmdbTVSeriesID", "genres", "certification", "voteAverage", "voteCount",
            "keywords", "watchProviders"
        ])
    }

    @Test
    func keysAreSorted() throws {
        let json = try Self.encode(Self.fullyPopulatedProgramme())
        let keyPattern = /"([A-Za-z]+)":/
        let keysInOrder = json.matches(of: keyPattern).map { String($0.output.1) }

        #expect(keysInOrder.count == 16)
        #expect(keysInOrder == keysInOrder.sorted())
    }

    @Test
    func fullyPopulatedProgrammeMatchesGoldenJSON() throws {
        let json = try Self.encode(Self.fullyPopulatedProgramme())

        // JSONEncoder escapes forward slashes by default; the output keeps them escaped.
        let expected = #"{"certification":"12A","description":"A thief steals secrets through dreams.","#
            + #""duration":9000,"episodeNumber":5,"genres":["Action","Science Fiction"],"#
            + #""imageURL":"https:\/\/example.com\/inception.jpg","isPremiere":true,"keywords":["dream","heist"],"#
            + #""seasonNumber":2,"startTime":1791288000,"title":"Inception","tmdbMovieID":27205,"#
            + #""tmdbTVSeriesID":1399,"voteAverage":8.5,"voteCount":37000,"watchProviders":["Sky Go","NOW"]}"#
        #expect(json == expected)
    }

}
