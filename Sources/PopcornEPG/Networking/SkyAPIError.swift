//
//  SkyAPIError.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

enum SkyAPIError: Error, CustomStringConvertible {

    case invalidURL(String)
    case httpError(statusCode: Int)
    case decodingError(Error)

    var description: String {
        switch self {
        case .invalidURL(let url):
            "Invalid URL: \(url)"
        case .httpError(let statusCode):
            "HTTP error: \(statusCode)"
        case .decodingError(let error):
            "Decoding error: \(error.localizedDescription)"
        }
    }

}
