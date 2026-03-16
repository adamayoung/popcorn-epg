//
//  EPGService.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

struct EPGService {

    private static let maxSubbouquetID = 20

    private let apiClient: SkyAPIClient
    private let maxConcurrentRequests: Int

    init(apiClient: SkyAPIClient = SkyAPIClient(), maxConcurrentRequests: Int = 20) {
        self.apiClient = apiClient
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    func fetchAllChannels() async -> [Channel] {
        let allServices = await fetchAllServices()
        return buildChannels(from: allServices)
    }

    func fetchSchedules(for channels: [Channel], dates: [String]) async -> EPGData {
        let schedulesBySID = await fetchAllSchedules(for: channels, dates: dates)
        let epgChannels = assembleChannels(channels, schedulesBySID: schedulesBySID, dates: dates)
        return EPGData(dates: dates, channels: epgChannels)
    }

}

// MARK: - Channel Fetching

extension EPGService {

    private func fetchAllServices() async -> [(service: SkyServicesResponse.Service, subbouquetID: Int)] {
        await withTaskGroup(
            of: [(service: SkyServicesResponse.Service, subbouquetID: Int)].self
        ) { group in
            for bouquet in Bouquet.all {
                for subbouquetID in 1 ... Self.maxSubbouquetID {
                    group.addTask {
                        do {
                            let response = try await apiClient.fetchServices(
                                bouquetID: bouquet.id, subbouquetID: subbouquetID
                            )
                            return response.services.map { (service: $0, subbouquetID: subbouquetID) }
                        } catch {
                            return []
                        }
                    }
                }
            }

            var results: [(service: SkyServicesResponse.Service, subbouquetID: Int)] = []
            for await batch in group {
                results.append(contentsOf: batch)
            }

            return results
        }
    }

    private func buildChannels(
        from allServices: [(service: SkyServicesResponse.Service, subbouquetID: Int)]
    ) -> [Channel] {
        var channelsBySID: [String: (service: SkyServicesResponse.Service, numbersBySub: [Int: String])] = [:]

        for (service, subbouquetID) in allServices {
            guard !service.isAdult else {
                continue
            }

            if var existing = channelsBySID[service.sid] {
                existing.numbersBySub[subbouquetID] = service.c
                channelsBySID[service.sid] = existing
            } else {
                channelsBySID[service.sid] = (service: service, numbersBySub: [subbouquetID: service.c])
            }
        }

        return channelsBySID.values.map { service, numbersBySub in
            var grouped: [String: [Int]] = [:]
            for (subbouquetID, channelNumber) in numbersBySub {
                grouped[channelNumber, default: []].append(subbouquetID)
            }

            let channelNumbers = grouped.map { channelNumber, subbouquetIDs in
                ChannelNumberMapping(
                    channelNumber: channelNumber,
                    subbouquetIDs: subbouquetIDs.sorted()
                )
            }.sorted { $0.channelNumber < $1.channelNumber }

            return Channel(
                sid: service.sid,
                name: service.t,
                logoURL: "https://epgstatic.sky.com/epgdata/1.0/newchanlogos/600/600/skychb\(service.sid).png",
                isHD: service.isHD,
                channelNumbers: channelNumbers,
                schedules: []
            )
        }
    }

}

// MARK: - Schedule Fetching

extension EPGService {

    private func fetchAllSchedules(
        for channels: [Channel],
        dates: [String]
    ) async -> [String: [String: [Programme]]] {
        let semaphore = AsyncSemaphore(limit: maxConcurrentRequests)

        var schedulesBySID: [String: [String: [Programme]]] = [:]
        for channel in channels {
            schedulesBySID[channel.sid] = [:]
        }

        for date in dates {
            await withTaskGroup(of: (String, [Programme]).self) { group in
                for channel in channels {
                    group.addTask {
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }
                        return await self.fetchChannelSchedule(channel: channel, date: date)
                    }
                }

                for await (sid, programmes) in group {
                    schedulesBySID[sid]?[date] = programmes
                }
            }

            print("Fetched schedule for \(date).")
        }

        return schedulesBySID
    }

    private func fetchChannelSchedule(channel: Channel, date: String) async -> (String, [Programme]) {
        let programmes: [Programme]
        do {
            let response = try await apiClient.fetchSchedule(date: date, sid: channel.sid)
            programmes = (response.schedule?.first?.events ?? []).map { event in
                let imageUUID = event.programmeuuid
                    ?? event.seasonuuid
                    ?? event.seriesuuid

                return Programme(
                    title: event.t,
                    description: Self.cleanDescription(event.sy),
                    startTime: event.st,
                    duration: event.d,
                    seasonNumber: event.seasonnumber,
                    episodeNumber: event.episodenumber,
                    isPremiere: event.new ?? false,
                    imageURL: imageUUID.map {
                        "https://images.metadata.sky.com/pd-image/\($0)/cover"
                    }
                )
            }
        } catch {
            print("Warning: Failed to fetch schedule for \(channel.name) (\(channel.sid)) on \(date): \(error)")
            programmes = []
        }

        return (channel.sid, programmes)
    }

    private func assembleChannels(
        _ channels: [Channel],
        schedulesBySID: [String: [String: [Programme]]],
        dates: [String]
    ) -> [Channel] {
        channels.compactMap { channel -> Channel? in
            guard let dateSchedules = schedulesBySID[channel.sid] else {
                return nil
            }

            let daySchedules = dates.compactMap { date -> DaySchedule? in
                guard let programmes = dateSchedules[date], !programmes.isEmpty else {
                    return nil
                }
                return DaySchedule(date: date, programmes: programmes)
            }

            guard !daySchedules.isEmpty else {
                return nil
            }

            var channelWithSchedules = channel
            channelWithSchedules.schedules = daySchedules
            return channelWithSchedules
        }
    }

}

// MARK: - Description Cleanup

extension EPGService {

    // swiftlint:disable:next force_try
    private static let featureTagPattern = try! NSRegularExpression(
        pattern: #"\s*\[(AD|HD|S|SL|W|BSL|3D|UHD|PG|CE|,\s*)*\]\s*"#
    )

    private static func cleanDescription(_ description: String?) -> String? {
        guard let description, !description.isEmpty else {
            return nil
        }

        let range = NSRange(description.startIndex..., in: description)
        let cleaned = featureTagPattern.stringByReplacingMatches(
            in: description, range: range, withTemplate: ""
        ).trimmingCharacters(in: .whitespaces)

        return cleaned.isEmpty ? nil : cleaned
    }

}

// MARK: - AsyncSemaphore

actor AsyncSemaphore {

    private let limit: Int
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
        self.permits = limit
    }

    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            permits += 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }

}
