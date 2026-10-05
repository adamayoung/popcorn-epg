//
//  TMDbFixtureBuilders.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import TMDb

/// Builders for EPG models and TMDb library types used by the TMDb tests.
enum TMDbFixtures {

    // MARK: - EPG

    static func programme(
        _ title: String,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        startTime: Int = 1_790_000_000
    ) -> Programme {
        Programme(
            title: title,
            description: "About \(title)",
            startTime: startTime,
            duration: 3600,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            isPremiere: false,
            imageURL: nil
        )
    }

    static func channel(_ sid: String, schedules: [DaySchedule]) -> Channel {
        Channel(
            sid: sid,
            name: "Channel \(sid)",
            logoURL: "https://example.com/\(sid).png",
            isHD: false,
            type: .tv,
            channelNumbers: [],
            schedules: schedules
        )
    }

    static func epgData(_ channels: [Channel]) -> EPGData {
        let dates = Array(Set(channels.flatMap { $0.schedules.map(\.date) })).sorted()
        return EPGData(dates: dates, channels: channels)
    }

    /// A single channel with a single day holding `programmes`.
    static func epgData(programmes: [Programme]) -> EPGData {
        epgData([channel("1000", schedules: [DaySchedule(date: "20261006", programmes: programmes)])])
    }

    // MARK: - Lookup service

    static func enrich(
        _ epgData: EPGData,
        stub: TMDbMetadataSourceStub,
        cache: TMDbCache = TMDbCache(fileURL: nil)
    ) async -> EPGData {
        await TMDbLookupService(metadataSource: stub, cache: cache).enrichProgrammes(in: epgData)
    }

    static func programmes(in epgData: EPGData) -> [Programme] {
        epgData.channels.flatMap { $0.schedules.flatMap(\.programmes) }
    }

    // MARK: - TMDb search

    static func movieList(ids: [Int]) -> MoviePageableList {
        MoviePageableList(
            results: ids.map { id in
                MovieListItem(
                    id: id,
                    title: "Movie \(id)",
                    originalTitle: "Movie \(id)",
                    originalLanguage: "en",
                    overview: "",
                    genreIDs: []
                )
            }
        )
    }

    static func tvSeriesList(ids: [Int]) -> TVSeriesPageableList {
        TVSeriesPageableList(
            results: ids.map { id in
                TVSeriesListItem(
                    id: id,
                    name: "Series \(id)",
                    originalName: "Series \(id)",
                    originalLanguage: "en",
                    overview: "",
                    genreIDs: [],
                    originCountries: []
                )
            }
        )
    }

    // MARK: - TMDb details

    static func movieDetails(
        id: Int,
        genres: [String]? = nil,
        voteAverage: Double? = nil,
        voteCount: Int? = nil,
        releaseDates: [MovieReleaseDatesByCountry]? = nil,
        keywords: [String]? = nil,
        watchProviders: [String: ShowWatchProvider]? = nil
    ) -> MovieDetailsResponse {
        MovieDetailsResponse(
            movie: Movie(
                id: id,
                title: "Movie \(id)",
                genres: genres.map(genreList),
                voteAverage: voteAverage,
                voteCount: voteCount
            ),
            releaseDates: releaseDates,
            keywords: keywords.map(keywordList),
            watchProviders: watchProviders
        )
    }

    static func tvSeriesDetails(
        id: Int,
        genres: [String]? = nil,
        voteAverage: Double? = nil,
        voteCount: Int? = nil,
        contentRatings: [ContentRating]? = nil,
        keywords: [String]? = nil,
        watchProviders: [String: ShowWatchProvider]? = nil
    ) -> TVSeriesDetailsResponse {
        TVSeriesDetailsResponse(
            tvSeries: TVSeries(
                id: id,
                name: "Series \(id)",
                genres: genres.map(genreList),
                voteAverage: voteAverage,
                voteCount: voteCount
            ),
            contentRatings: contentRatings,
            keywords: keywords.map(keywordList),
            watchProviders: watchProviders
        )
    }

    static func releaseDates(_ countryCode: String, certifications: [String]) -> MovieReleaseDatesByCountry {
        MovieReleaseDatesByCountry(
            countryCode: countryCode,
            releaseDates: certifications.map { certification in
                ReleaseDate(
                    certification: certification,
                    releaseDate: Date(timeIntervalSince1970: 1_700_000_000),
                    type: .theatrical
                )
            }
        )
    }

    static func contentRating(_ countryCode: String, rating: String) -> ContentRating {
        ContentRating(descriptors: [], countryCode: countryCode, rating: rating)
    }

    static func providers(_ names: [String]) -> [WatchProvider] {
        names.enumerated().map { index, name in WatchProvider(id: index + 1, name: name) }
    }

    private static func genreList(_ names: [String]) -> [Genre] {
        names.enumerated().map { index, name in Genre(id: index + 1, name: name) }
    }

    private static func keywordList(_ names: [String]) -> [Keyword] {
        names.enumerated().map { index, name in Keyword(id: index + 1, name: name) }
    }

    // MARK: - Cache

    static func cacheEntry(
        movieID: Int? = nil,
        tvSeriesID: Int? = nil,
        cachedAt: Date,
        genres: [String]? = nil,
        certification: String? = nil,
        voteAverage: Double? = nil,
        voteCount: Int? = nil,
        keywords: [String]? = nil,
        watchProviders: [String]? = nil
    ) -> TMDbCacheEntry {
        TMDbCacheEntry(
            tmdbMovieID: movieID,
            tmdbTVSeriesID: tvSeriesID,
            cachedAt: cachedAt,
            genres: genres,
            certification: certification,
            voteAverage: voteAverage,
            voteCount: voteCount,
            keywords: keywords,
            watchProviders: watchProviders
        )
    }

}

/// The TMDb-derived fields shared by `Programme` and `TMDbCacheEntry`, so tests can compare them in one `#expect`.
struct TMDbFields: Equatable {

    var tmdbMovieID: Int?
    var tmdbTVSeriesID: Int?
    var genres: [String]?
    var certification: String?
    var voteAverage: Double?
    var voteCount: Int?
    var keywords: [String]?
    var watchProviders: [String]?

    static let empty = TMDbFields()

    init(
        tmdbMovieID: Int? = nil,
        tmdbTVSeriesID: Int? = nil,
        genres: [String]? = nil,
        certification: String? = nil,
        voteAverage: Double? = nil,
        voteCount: Int? = nil,
        keywords: [String]? = nil,
        watchProviders: [String]? = nil
    ) {
        self.tmdbMovieID = tmdbMovieID
        self.tmdbTVSeriesID = tmdbTVSeriesID
        self.genres = genres
        self.certification = certification
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.keywords = keywords
        self.watchProviders = watchProviders
    }

    init(_ programme: Programme) {
        self.init(
            tmdbMovieID: programme.tmdbMovieID,
            tmdbTVSeriesID: programme.tmdbTVSeriesID,
            genres: programme.genres,
            certification: programme.certification,
            voteAverage: programme.voteAverage,
            voteCount: programme.voteCount,
            keywords: programme.keywords,
            watchProviders: programme.watchProviders
        )
    }

    init(_ entry: TMDbCacheEntry) {
        self.init(
            tmdbMovieID: entry.tmdbMovieID,
            tmdbTVSeriesID: entry.tmdbTVSeriesID,
            genres: entry.genres,
            certification: entry.certification,
            voteAverage: entry.voteAverage,
            voteCount: entry.voteCount,
            keywords: entry.keywords,
            watchProviders: entry.watchProviders
        )
    }

}
