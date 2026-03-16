//
//  SkyScheduleResponse.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

import Foundation

struct SkyScheduleResponse: Decodable {

    let schedule: [ScheduleEntry]?

    struct ScheduleEntry: Decodable {
        let sid: String
        let events: [Event]?
    }

    struct Event: Decodable {
        let st: Int
        let d: Int
        let t: String
        let sy: String?
        let seasonnumber: Int?
        let episodenumber: Int?
        let programmeuuid: String?
        let seasonuuid: String?
        let seriesuuid: String?
        let new: Bool?

        enum CodingKeys: String, CodingKey {
            case st, d, t, sy
            case seasonnumber, episodenumber
            case programmeuuid, seasonuuid, seriesuuid
            case new
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.st = try container.decode(Int.self, forKey: .st)
            self.d = try container.decode(Int.self, forKey: .d)
            self.t = try container.decode(String.self, forKey: .t)
            self.sy = try container.decodeIfPresent(String.self, forKey: .sy)
            self.seasonnumber = try container.decodeIfPresent(Int.self, forKey: .seasonnumber)
            self.episodenumber = try container.decodeIfPresent(Int.self, forKey: .episodenumber)
            self.programmeuuid = try container.decodeIfPresent(String.self, forKey: .programmeuuid)
            self.seasonuuid = try container.decodeIfPresent(String.self, forKey: .seasonuuid)
            self.seriesuuid = try container.decodeIfPresent(String.self, forKey: .seriesuuid)
            self.new = try container.decodeIfPresent(Bool.self, forKey: .new)
        }
    }

}
