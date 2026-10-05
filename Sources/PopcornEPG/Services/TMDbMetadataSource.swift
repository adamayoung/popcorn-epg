//
//  TMDbMetadataSource.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
import TMDb

/// The four TMDb calls the lookup service makes, so tests can substitute canned responses.
protocol TMDbMetadataSource: Sendable {

    func searchMovies(query: String) async throws -> MoviePageableList

    func searchTVSeries(query: String) async throws -> TVSeriesPageableList

    func movieDetails(forMovie id: Int, appending: MovieAppendOption) async throws -> MovieDetailsResponse

    func tvSeriesDetails(forTVSeries id: Int, appending: TVSeriesAppendOption) async throws -> TVSeriesDetailsResponse

}

extension TMDbClient: TMDbMetadataSource {

    func searchMovies(query: String) async throws -> MoviePageableList {
        try await search.searchMovies(query: query, filter: nil, page: nil, language: nil)
    }

    func searchTVSeries(query: String) async throws -> TVSeriesPageableList {
        try await search.searchTVSeries(query: query, filter: nil, page: nil, language: nil)
    }

    func movieDetails(forMovie id: Int, appending: MovieAppendOption) async throws -> MovieDetailsResponse {
        try await movies.details(forMovie: id, appending: appending, language: nil)
    }

    func tvSeriesDetails(forTVSeries id: Int, appending: TVSeriesAppendOption) async throws -> TVSeriesDetailsResponse {
        try await tvSeries.details(forTVSeries: id, appending: appending, language: nil)
    }

}
