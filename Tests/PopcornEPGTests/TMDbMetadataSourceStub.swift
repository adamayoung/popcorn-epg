//
//  TMDbMetadataSourceStub.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation
@testable import PopcornEPG
import TMDb

/// Returns canned search results and details keyed by title/ID, and records every call.
/// A details request for an ID with no canned response throws.
final class TMDbMetadataSourceStub: TMDbMetadataSource, @unchecked Sendable {

    enum Call: Equatable {
        case searchMovies(String)
        case searchTVSeries(String)
        case movieDetails(Int, MovieAppendOption)
        case tvSeriesDetails(Int, TVSeriesAppendOption)
    }

    struct StubError: Error {}

    private let movieIDsByTitle: [String: Int]
    private let tvSeriesIDsByTitle: [String: Int]
    private let failingSearchTitles: Set<String>
    private let movieDetailsByID: [Int: MovieDetailsResponse]
    private let tvSeriesDetailsByID: [Int: TVSeriesDetailsResponse]

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    init(
        movieIDsByTitle: [String: Int] = [:],
        tvSeriesIDsByTitle: [String: Int] = [:],
        failingSearchTitles: Set<String> = [],
        movieDetailsByID: [Int: MovieDetailsResponse] = [:],
        tvSeriesDetailsByID: [Int: TVSeriesDetailsResponse] = [:]
    ) {
        self.movieIDsByTitle = movieIDsByTitle
        self.tvSeriesIDsByTitle = tvSeriesIDsByTitle
        self.failingSearchTitles = failingSearchTitles
        self.movieDetailsByID = movieDetailsByID
        self.tvSeriesDetailsByID = tvSeriesDetailsByID
    }

    var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    func searchMovies(query: String) async throws -> MoviePageableList {
        record(.searchMovies(query))
        if failingSearchTitles.contains(query) {
            throw StubError()
        }

        return TMDbFixtures.movieList(ids: movieIDsByTitle[query].map { [$0] } ?? [])
    }

    func searchTVSeries(query: String) async throws -> TVSeriesPageableList {
        record(.searchTVSeries(query))
        if failingSearchTitles.contains(query) {
            throw StubError()
        }

        return TMDbFixtures.tvSeriesList(ids: tvSeriesIDsByTitle[query].map { [$0] } ?? [])
    }

    func movieDetails(forMovie id: Int, appending: MovieAppendOption) async throws -> MovieDetailsResponse {
        record(.movieDetails(id, appending))
        guard let response = movieDetailsByID[id] else {
            throw StubError()
        }

        return response
    }

    func tvSeriesDetails(forTVSeries id: Int, appending: TVSeriesAppendOption) async throws -> TVSeriesDetailsResponse {
        record(.tvSeriesDetails(id, appending))
        guard let response = tvSeriesDetailsByID[id] else {
            throw StubError()
        }

        return response
    }

    private func record(_ call: Call) {
        lock.withLock { recordedCalls.append(call) }
    }

}
