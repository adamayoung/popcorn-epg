//
//  TMDbLookupServiceMappingTests.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import Testing
import TMDb

/// How TMDb details responses are mapped onto programmes, including the GB-only field extraction.
struct TMDbLookupServiceMappingTests {

    private typealias Fixtures = TMDbFixtures

    @Test
    func movieDetailsAreMappedOntoProgramme() async {
        let gbProviders = ShowWatchProvider(
            free: Fixtures.providers(["BBC iPlayer", "Netflix"]),
            flatRate: Fixtures.providers(["Netflix", "Disney Plus"]),
            buy: Fixtures.providers(["Apple TV Store"]),
            rent: Fixtures.providers(["Amazon Video"]),
            ads: Fixtures.providers(["ITVX", "Disney Plus"])
        )
        let details = Fixtures.movieDetails(
            id: 949,
            genres: ["Action", "Crime"],
            voteAverage: 7.9,
            voteCount: 7200,
            releaseDates: [
                Fixtures.releaseDates("US", certifications: ["R"]),
                Fixtures.releaseDates("GB", certifications: ["", "15", "18"])
            ],
            keywords: ["heist", "los angeles"],
            watchProviders: ["US": ShowWatchProvider(flatRate: Fixtures.providers(["Hulu"])), "GB": gbProviders]
        )
        let stub = TMDbMetadataSourceStub(movieIDsByTitle: ["Heat": 949], movieDetailsByID: [949: details])

        let enriched = await Fixtures.enrich(Fixtures.epgData(programmes: [Fixtures.programme("Heat")]), stub: stub)

        #expect(Fixtures.programmes(in: enriched).map(TMDbFields.init) == [
            TMDbFields(
                tmdbMovieID: 949,
                genres: ["Action", "Crime"],
                certification: "15",
                voteAverage: 7.9,
                voteCount: 7200,
                keywords: ["heist", "los angeles"],
                watchProviders: ["Netflix", "Disney Plus", "ITVX", "BBC iPlayer"]
            )
        ])
    }

    @Test
    func tvSeriesDetailsAreMappedOntoProgramme() async {
        let details = Fixtures.tvSeriesDetails(
            id: 57243,
            genres: ["Sci-Fi & Fantasy", "Drama"],
            voteAverage: 7.5,
            voteCount: 3100,
            contentRatings: [
                Fixtures.contentRating("US", rating: "TV-PG"),
                Fixtures.contentRating("GB", rating: "PG")
            ],
            keywords: ["time travel"],
            watchProviders: [
                "GB": ShowWatchProvider(
                    free: Fixtures.providers(["BBC iPlayer"]),
                    buy: Fixtures.providers(["Apple TV Store"])
                ),
                "US": ShowWatchProvider(flatRate: Fixtures.providers(["Max"]))
            ]
        )
        let stub = TMDbMetadataSourceStub(
            tvSeriesIDsByTitle: ["Doctor Who": 57243],
            tvSeriesDetailsByID: [57243: details]
        )

        let enriched = await Fixtures.enrich(
            Fixtures.epgData(programmes: [Fixtures.programme("Doctor Who", episodeNumber: 3)]),
            stub: stub
        )

        #expect(Fixtures.programmes(in: enriched).map(TMDbFields.init) == [
            TMDbFields(
                tmdbTVSeriesID: 57243,
                genres: ["Sci-Fi & Fantasy", "Drama"],
                certification: "PG",
                voteAverage: 7.5,
                voteCount: 3100,
                keywords: ["time travel"],
                watchProviders: ["BBC iPlayer"]
            )
        ])
    }

    @Test
    func emptyDetailArraysBecomeNilAndAreOmittedFromJSON() async throws {
        let details = Fixtures.movieDetails(
            id: 5,
            genres: [],
            releaseDates: [Fixtures.releaseDates("GB", certifications: ["", ""])],
            keywords: [],
            watchProviders: ["GB": ShowWatchProvider(free: [], flatRate: [], ads: [])]
        )
        let stub = TMDbMetadataSourceStub(movieIDsByTitle: ["Obscure": 5], movieDetailsByID: [5: details])

        let enriched = await Fixtures.enrich(Fixtures.epgData(programmes: [Fixtures.programme("Obscure")]), stub: stub)

        let programme = try #require(Fixtures.programmes(in: enriched).first)
        #expect(TMDbFields(programme) == TMDbFields(tmdbMovieID: 5))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(programme)) as? [String: Any]
        let keys = try Set(#require(json).keys)
        #expect(keys.isDisjoint(with: ["genres", "certification", "keywords", "watchProviders"]))
        #expect(keys.contains("tmdbMovieID"))
    }

    @Test
    func movieCertificationIsNilWithoutNonEmptyGBRelease() {
        #expect(TMDbLookupService.gbCertification(from: [Fixtures.releaseDates("US", certifications: ["R"])]) == nil)
        #expect(TMDbLookupService.gbCertification(from: [Fixtures.releaseDates("GB", certifications: [""])]) == nil)
        #expect(TMDbLookupService.gbCertification(from: [MovieReleaseDatesByCountry]()) == nil)
    }

    @Test
    func tvCertificationIsNilWithoutNonEmptyGBRating() {
        #expect(TMDbLookupService.gbCertification(from: [Fixtures.contentRating("US", rating: "TV-MA")]) == nil)
        #expect(TMDbLookupService.gbCertification(from: [Fixtures.contentRating("GB", rating: "")]) == nil)
        #expect(TMDbLookupService.gbCertification(from: [ContentRating]()) == nil)
    }

    @Test
    func watchProvidersAreNilWithoutGBStreaming() {
        #expect(TMDbLookupService.gbWatchProviders(from: nil) == nil)
        #expect(TMDbLookupService.gbWatchProviders(
            from: ["US": ShowWatchProvider(flatRate: Fixtures.providers(["Hulu"]))]
        ) == nil)
        #expect(TMDbLookupService.gbWatchProviders(
            from: ["GB": ShowWatchProvider(
                buy: Fixtures.providers(["Apple TV Store"]),
                rent: Fixtures.providers(["Amazon Video"])
            )]
        ) == nil)
    }

}
