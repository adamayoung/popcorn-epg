//
//  Programme.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

struct Programme: Encodable {

    let title: String
    let description: String?
    let startTime: Int
    let duration: Int
    let seasonNumber: Int?
    let episodeNumber: Int?
    let isPremiere: Bool
    let imageURL: String?
    var tmdbMovieID: Int?
    var tmdbTVSeriesID: Int?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(seasonNumber, forKey: .seasonNumber)
        try container.encodeIfPresent(episodeNumber, forKey: .episodeNumber)
        if isPremiere {
            try container.encode(isPremiere, forKey: .isPremiere)
        }
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(tmdbMovieID, forKey: .tmdbMovieID)
        try container.encodeIfPresent(tmdbTVSeriesID, forKey: .tmdbTVSeriesID)
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, startTime, duration
        case seasonNumber, episodeNumber, isPremiere
        case imageURL, tmdbMovieID, tmdbTVSeriesID
    }

}
