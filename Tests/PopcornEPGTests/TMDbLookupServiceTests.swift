//
//  TMDbLookupServiceTests.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import Testing
import TMDb

struct TMDbLookupServiceTests {

    private typealias Fixtures = TMDbFixtures

    private static let movieAppendOptions: MovieAppendOption = [.releaseDates, .keywords, .watchProviders]
    private static let tvSeriesAppendOptions: TVSeriesAppendOption = [.contentRatings, .keywords, .watchProviders]

    // MARK: - collectUniqueTitles

    @Test
    func collectUniqueTitlesTreatsSeasonOrEpisodeNumberAsTVSeries() {
        let service = TMDbLookupService(metadataSource: TMDbMetadataSourceStub(), cache: TMDbCache(fileURL: nil))
        let epgData = Fixtures.epgData(programmes: [
            Fixtures.programme("Season Only", seasonNumber: 2),
            Fixtures.programme("Episode Only", episodeNumber: 5),
            Fixtures.programme("Both", seasonNumber: 1, episodeNumber: 1),
            Fixtures.programme("Neither")
        ])

        let titles = service.collectUniqueTitles(from: epgData)

        #expect(titles == ["Season Only": true, "Episode Only": true, "Both": true, "Neither": false])
    }

    @Test
    func collectUniqueTitlesLetsFirstOccurrenceDecide() {
        let service = TMDbLookupService(metadataSource: TMDbMetadataSourceStub(), cache: TMDbCache(fileURL: nil))
        let epgData = Fixtures.epgData([
            Fixtures.channel("1", schedules: [
                DaySchedule(date: "20261006", programmes: [
                    Fixtures.programme("Film Then Show"),
                    Fixtures.programme("Show Then Film", seasonNumber: 1, episodeNumber: 1)
                ])
            ]),
            Fixtures.channel("2", schedules: [
                DaySchedule(date: "20261006", programmes: [
                    Fixtures.programme("Film Then Show", seasonNumber: 3, episodeNumber: 4),
                    Fixtures.programme("Show Then Film")
                ])
            ])
        ])

        let titles = service.collectUniqueTitles(from: epgData)

        #expect(titles == ["Film Then Show": false, "Show Then Film": true])
    }

    @Test
    func collectUniqueTitlesDeduplicatesAcrossChannelsAndDays() {
        let service = TMDbLookupService(metadataSource: TMDbMetadataSourceStub(), cache: TMDbCache(fileURL: nil))
        let epgData = Fixtures.epgData([
            Fixtures.channel("1", schedules: [
                DaySchedule(date: "20261006", programmes: [Fixtures.programme("News"), Fixtures.programme("Film")]),
                DaySchedule(date: "20261007", programmes: [Fixtures.programme("News")])
            ]),
            Fixtures.channel("2", schedules: [
                DaySchedule(date: "20261006", programmes: [Fixtures.programme("Film"), Fixtures.programme("Quiz")])
            ])
        ])

        let titles = service.collectUniqueTitles(from: epgData)

        #expect(Set(titles.keys) == ["News", "Film", "Quiz"])
    }

    // MARK: - Resolution order

    @Test
    func episodicTitleSearchesTVOnly() async {
        let stub = TMDbMetadataSourceStub(
            movieIDsByTitle: ["Doctor Who": 1],
            tvSeriesIDsByTitle: ["Doctor Who": 57243]
        )

        let enriched = await Fixtures.enrich(
            Fixtures.epgData(programmes: [Fixtures.programme("Doctor Who", seasonNumber: 1, episodeNumber: 2)]),
            stub: stub
        )

        #expect(stub.calls == [
            .searchTVSeries("Doctor Who"),
            .tvSeriesDetails(57243, Self.tvSeriesAppendOptions)
        ])
        #expect(Fixtures.programmes(in: enriched).first?.tmdbTVSeriesID == 57243)
    }

    @Test
    func nonEpisodicTitleFoundAsMovieDoesNotSearchTV() async {
        let stub = TMDbMetadataSourceStub(
            movieIDsByTitle: ["Heat": 949],
            tvSeriesIDsByTitle: ["Heat": 2]
        )

        let enriched = await Fixtures.enrich(Fixtures.epgData(programmes: [Fixtures.programme("Heat")]), stub: stub)

        #expect(stub.calls == [.searchMovies("Heat"), .movieDetails(949, Self.movieAppendOptions)])
        let programme = Fixtures.programmes(in: enriched).first
        #expect(programme?.tmdbMovieID == 949)
        #expect(programme?.tmdbTVSeriesID == nil)
    }

    @Test
    func nonEpisodicTitleFallsBackToTVWhenNoMovieFound() async {
        let stub = TMDbMetadataSourceStub(tvSeriesIDsByTitle: ["Panorama": 3000])

        let enriched = await Fixtures.enrich(Fixtures.epgData(programmes: [Fixtures.programme("Panorama")]), stub: stub)

        #expect(stub.calls == [
            .searchMovies("Panorama"),
            .searchTVSeries("Panorama"),
            .tvSeriesDetails(3000, Self.tvSeriesAppendOptions)
        ])
        let programme = Fixtures.programmes(in: enriched).first
        #expect(programme?.tmdbMovieID == nil)
        #expect(programme?.tmdbTVSeriesID == 3000)
    }

    @Test
    func titleFoundNowhereIsCachedWithoutIDsOrDetails() async throws {
        let stub = TMDbMetadataSourceStub()
        let cache = TMDbCache(fileURL: nil)

        let enriched = await Fixtures.enrich(
            Fixtures.epgData(programmes: [Fixtures.programme("Local Weather")]),
            stub: stub,
            cache: cache
        )

        #expect(stub.calls == [.searchMovies("Local Weather"), .searchTVSeries("Local Weather")])
        let entry = try #require(await cache.lookup("Local Weather"))
        #expect(!entry.hasResult)
        #expect(TMDbFields(entry) == .empty)
        #expect(Fixtures.programmes(in: enriched).map(TMDbFields.init) == [.empty])
    }

    @Test
    func throwingSearchIsTreatedAsNotFoundAndOtherTitlesContinue() async throws {
        let stub = TMDbMetadataSourceStub(
            movieIDsByTitle: ["Broken": 1, "Heat": 949],
            failingSearchTitles: ["Broken"],
            movieDetailsByID: [949: Fixtures.movieDetails(id: 949, voteCount: 10)]
        )
        let cache = TMDbCache(fileURL: nil)

        let enriched = await Fixtures.enrich(
            Fixtures.epgData(programmes: [Fixtures.programme("Broken"), Fixtures.programme("Heat")]),
            stub: stub,
            cache: cache
        )

        let brokenEntry = try #require(await cache.lookup("Broken"))
        #expect(TMDbFields(brokenEntry) == .empty)
        // The movie search throwing exits the shared do/catch, so TV is never tried for this title.
        #expect(stub.calls.filter { $0 == .searchMovies("Broken") || $0 == .searchTVSeries("Broken") } == [
            .searchMovies("Broken")
        ])
        let programmes = Fixtures.programmes(in: enriched)
        #expect(programmes.map(\.tmdbMovieID) == [nil, 949])
        #expect(programmes.map(\.voteCount) == [nil, 10])
    }

    // MARK: - Details failure

    @Test
    func throwingDetailsRequestKeepsIDButHasNoDetailFields() async throws {
        let stub = TMDbMetadataSourceStub(movieIDsByTitle: ["Heat": 949])
        let cache = TMDbCache(fileURL: nil)

        let enriched = await Fixtures.enrich(
            Fixtures.epgData(programmes: [Fixtures.programme("Heat")]),
            stub: stub,
            cache: cache
        )

        #expect(stub.calls == [.searchMovies("Heat"), .movieDetails(949, Self.movieAppendOptions)])
        let entry = try #require(await cache.lookup("Heat"))
        #expect(TMDbFields(entry) == TMDbFields(tmdbMovieID: 949))
        #expect(Fixtures.programmes(in: enriched).map(TMDbFields.init) == [TMDbFields(tmdbMovieID: 949)])
    }

    // MARK: - Cache interaction

    @Test
    func cachedTitleIsNotLookedUpAndItsFieldsAreApplied() async {
        let stub = TMDbMetadataSourceStub(movieIDsByTitle: ["Heat": 949])
        let cache = TMDbCache(fileURL: nil)
        await cache.set("Heat", entry: Fixtures.cacheEntry(movieID: 1, cachedAt: Date(), certification: "15"))

        let enriched = await Fixtures.enrich(
            Fixtures.epgData(programmes: [Fixtures.programme("Heat")]),
            stub: stub,
            cache: cache
        )

        #expect(stub.calls.isEmpty)
        #expect(Fixtures.programmes(in: enriched).map(TMDbFields.init) == [
            TMDbFields(tmdbMovieID: 1, certification: "15")
        ])
    }

    @Test
    func expiredCachedTitleIsLookedUpAgain() async throws {
        let stub = TMDbMetadataSourceStub(
            movieIDsByTitle: ["Heat": 949],
            movieDetailsByID: [949: Fixtures.movieDetails(id: 949, voteCount: 7200)]
        )
        let cache = TMDbCache(fileURL: nil)
        let thirtyOneDaysAgo = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        await cache.set("Heat", entry: Fixtures.cacheEntry(movieID: 1, cachedAt: thirtyOneDaysAgo))

        let enriched = await Fixtures.enrich(
            Fixtures.epgData(programmes: [Fixtures.programme("Heat")]),
            stub: stub,
            cache: cache
        )

        #expect(stub.calls == [.searchMovies("Heat"), .movieDetails(949, Self.movieAppendOptions)])
        let programme = try #require(Fixtures.programmes(in: enriched).first)
        #expect(programme.tmdbMovieID == 949)
        #expect(programme.voteCount == 7200)
    }

    // MARK: - Enrichment

    @Test
    func enrichmentAppliesToEveryMatchingProgrammeAndLeavesOthersUntouched() async {
        let stub = TMDbMetadataSourceStub(
            movieIDsByTitle: ["Heat": 949],
            movieDetailsByID: [949: Fixtures.movieDetails(id: 949, genres: ["Crime"], voteCount: 7200)]
        )
        let epgData = Fixtures.epgData([
            Fixtures.channel("1", schedules: [
                DaySchedule(date: "20261006", programmes: [
                    Fixtures.programme("Heat", startTime: 100),
                    Fixtures.programme("Unknown Show", startTime: 200)
                ]),
                DaySchedule(date: "20261007", programmes: [Fixtures.programme("Heat", startTime: 300)])
            ]),
            Fixtures.channel("2", schedules: [
                DaySchedule(date: "20261006", programmes: [Fixtures.programme("Heat", startTime: 400)])
            ])
        ])

        let enriched = await Fixtures.enrich(epgData, stub: stub)

        #expect(enriched.dates == epgData.dates)
        #expect(enriched.channels.map(\.sid) == ["1", "2"])
        #expect(enriched.channels.map { $0.schedules.map(\.date) } == [["20261006", "20261007"], ["20261006"]])

        let programmes = Fixtures.programmes(in: enriched)
        #expect(programmes.map(\.title) == ["Heat", "Unknown Show", "Heat", "Heat"])
        #expect(programmes.map(\.startTime) == [100, 200, 300, 400])
        let heatFields = TMDbFields(tmdbMovieID: 949, genres: ["Crime"], voteCount: 7200)
        #expect(programmes.map(TMDbFields.init) == [heatFields, .empty, heatFields, heatFields])
        #expect(programmes.map(\.description) == programmes.map { "About \($0.title)" })
        // One search per unique title, however many airings it has.
        #expect(stub.calls.filter { $0 == .searchMovies("Heat") }.count == 1)
    }

}
