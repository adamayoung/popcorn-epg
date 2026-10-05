//
//  EPGService.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

struct EPGService {

    private static let maxSubbouquetID = 20
    /// The schedule endpoint rejects requests for more than 20 SIDs with HTTP 400 ("Invalid sid count").
    private static let maxSIDsPerScheduleRequest = 20

    private let apiClient: any SkyAPI
    private let maxConcurrentRequests: Int

    init(apiClient: any SkyAPI, maxConcurrentRequests: Int = 20) {
        self.apiClient = apiClient
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    init(maxConcurrentRequests: Int = 20) {
        self.init(
            apiClient: SkyAPIClient(maxConnectionsPerHost: maxConcurrentRequests),
            maxConcurrentRequests: maxConcurrentRequests
        )
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

    private func fetchAllServices() async -> [(service: SkyServicesResponse.Service, region: RegionRef)] {
        await withTaskGroup(
            of: [(service: SkyServicesResponse.Service, region: RegionRef)].self
        ) { group in
            for bouquet in Bouquet.all {
                for subbouquetID in 1 ... Self.maxSubbouquetID {
                    group.addTask {
                        do {
                            let response = try await apiClient.fetchServices(
                                bouquetID: bouquet.id, subbouquetID: subbouquetID
                            )
                            let region = RegionRef(bouquet: bouquet.id, subBouquet: subbouquetID)
                            return response.services.map { (service: $0, region: region) }
                        } catch {
                            return []
                        }
                    }
                }
            }

            var results: [(service: SkyServicesResponse.Service, region: RegionRef)] = []
            for await batch in group {
                results.append(contentsOf: batch)
            }

            return results
        }
    }

    func buildChannels(
        from allServices: [(service: SkyServicesResponse.Service, region: RegionRef)]
    ) -> [Channel] {
        var channelsBySID: [String: (service: SkyServicesResponse.Service, numbersByRegion: [RegionRef: String])] = [:]

        for (service, region) in allServices {
            guard !service.isAdult else {
                continue
            }

            if var existing = channelsBySID[service.sid] {
                existing.numbersByRegion[region] = service.c
                channelsBySID[service.sid] = existing
            } else {
                channelsBySID[service.sid] = (service: service, numbersByRegion: [region: service.c])
            }
        }

        return channelsBySID.values.map { service, numbersByRegion in
            var grouped: [String: [RegionRef]] = [:]
            for (region, channelNumber) in numbersByRegion {
                grouped[channelNumber, default: []].append(region)
            }

            let channelNumbers = grouped.map { channelNumber, regions in
                ChannelNumberMapping(
                    channelNumber: channelNumber,
                    regions: regions.sorted { ($0.bouquet, $0.subBouquet) < ($1.bouquet, $1.subBouquet) }
                )
            }.sorted { $0.channelNumber < $1.channelNumber }

            return Channel(
                sid: service.sid,
                name: service.t,
                logoURL: "https://epgstatic.sky.com/epgdata/1.0/newchanlogos/600/600/skychb\(service.sid).png",
                isHD: service.isHD,
                type: service.isRadio ? .radio : .tv,
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

        let channelBatches = Self.scheduleRequestBatches(of: channels)

        for date in dates {
            await withTaskGroup(of: [(String, [Programme])].self) { group in
                for batch in channelBatches {
                    group.addTask {
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }
                        return await self.fetchBatchSchedules(channels: batch, date: date)
                    }
                }

                for await results in group {
                    for (sid, programmes) in results {
                        schedulesBySID[sid]?[date] = programmes
                    }
                }
            }

            print("Fetched schedule for \(date).")
        }

        return schedulesBySID
    }

    static func scheduleRequestBatches(of channels: [Channel]) -> [[Channel]] {
        stride(from: 0, to: channels.count, by: maxSIDsPerScheduleRequest).map { start in
            Array(channels[start ..< min(start + maxSIDsPerScheduleRequest, channels.count)])
        }
    }

    private func fetchBatchSchedules(channels: [Channel], date: String) async -> [(String, [Programme])] {
        if channels.count == 1, let channel = channels.first {
            return await [fetchChannelSchedule(channel: channel, date: date)]
        }

        do {
            let response = try await apiClient.fetchSchedule(date: date, sids: channels.map(\.sid))
            let eventsBySID = Self.eventsBySID(in: response)
            return channels.map { channel in
                (channel.sid, Self.programmes(from: eventsBySID[channel.sid] ?? []))
            }
        } catch {
            print("Warning: Failed to fetch schedule batch of \(channels.count) channels on \(date): \(error)")
            var results: [(String, [Programme])] = []
            for channel in channels {
                await results.append(fetchChannelSchedule(channel: channel, date: date))
            }
            return results
        }
    }

    private func fetchChannelSchedule(channel: Channel, date: String) async -> (String, [Programme]) {
        let programmes: [Programme]
        do {
            let response = try await apiClient.fetchSchedule(date: date, sids: [channel.sid])
            programmes = Self.programmes(from: response.schedule?.first?.events ?? [])
        } catch {
            print("Warning: Failed to fetch schedule for \(channel.name) (\(channel.sid)) on \(date): \(error)")
            programmes = []
        }

        return (channel.sid, programmes)
    }

    static func eventsBySID(in response: SkyScheduleResponse) -> [String: [SkyScheduleResponse.Event]] {
        let entries = (response.schedule ?? []).map { ($0.sid, $0.events ?? []) }
        return Dictionary(entries) { first, _ in first }
    }

    static func programmes(from events: [SkyScheduleResponse.Event]) -> [Programme] {
        events.map { event in
            let imageUUID = event.programmeuuid
                ?? event.seasonuuid
                ?? event.seriesuuid

            return Programme(
                title: event.t,
                description: cleanDescription(event.sy),
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

    static func cleanDescription(_ description: String?) -> String? {
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
