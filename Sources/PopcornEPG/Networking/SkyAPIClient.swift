//
//  SkyAPIClient.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct SkyAPIClient {

    private static let baseURL = "https://awk.epgsky.com/hawk/linear"
    private static let maxRetries = 3
    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchServices(bouquetID: Int, subbouquetID: Int) async throws -> SkyServicesResponse {
        let urlString = "\(Self.baseURL)/services/\(bouquetID)/\(subbouquetID)"
        return try await fetch(urlString)
    }

    func fetchSchedule(date: String, sid: String) async throws -> SkyScheduleResponse {
        let urlString = "\(Self.baseURL)/schedule/\(date)/\(sid)"
        return try await fetch(urlString)
    }

    private func fetch<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw SkyAPIError.invalidURL(urlString)
        }

        var lastError: Error?

        for attempt in 0 ..< Self.maxRetries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
            }

            do {
                let (data, response) = try await urlSession.data(from: url)

                if let httpResponse = response as? HTTPURLResponse {
                    if (200 ..< 300).contains(httpResponse.statusCode) {
                        return try JSONDecoder().decode(T.self, from: data)
                    }

                    if Self.retryableStatusCodes.contains(httpResponse.statusCode) {
                        lastError = SkyAPIError.httpError(statusCode: httpResponse.statusCode)
                        continue
                    }

                    throw SkyAPIError.httpError(statusCode: httpResponse.statusCode)
                }

                return try JSONDecoder().decode(T.self, from: data)
            } catch let error as SkyAPIError {
                throw error
            } catch let error as DecodingError {
                throw SkyAPIError.decodingError(error)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? SkyAPIError.httpError(statusCode: 0)
    }

}
