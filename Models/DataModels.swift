//
//  DataModels.swift
//  aau-sw8-ios
//
//  Created by jimpo on 19/02/26.
//  The data models need to match with the backend and indoor data pipeline, work alongside the other members

import Foundation
import CoreLocation
import Combine

extension CLLocationCoordinate2D: @retroactive Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(latitude)
        try container.encode(longitude)
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let lat = try container.decode(Double.self)
        let lon = try container.decode(Double.self)
        self.init(latitude: lat, longitude: lon)
    }
}


// General building
struct Building: Identifiable, Codable {
    let id: String                   // UUID or backend ID
    var name: String
    var type: BuildingType
    var address: String?
    var floors: [Floor]              // Contains floor maps, rooms
    // var metadata: [String: String]? // Custom building data
}

// Building types in which the app could be used
enum BuildingType: String, Codable {
    case mall
    case hotel
    case airport
    case hospital
    case museum
    case library
    case campus
    case venue
    case other
}

// General floor
struct Floor: Identifiable, Codable {
    let id: String
    //var name: String                 // Ground Floor, etc... but i don't think it's needed if there are levels already
    var levelIndex: Int
    //var mapImageURL: URL?            // Optional floor map
    var mapVectorData: FloorGeometry? // Optional vector geometry (rooms, hallways)
    var rooms: [Room]                  // Rooms
    var pois: [POI]                    // Points of interest: restrooms, exits, elevators
}

// What a "Room" could be, it can even be store, restaurant, etc...
struct Room: Identifiable, Codable {
    let id: String
    var name: String                     // "Room 2.228", "Gate A12", "McDonald's",
    var type: RoomType
    var centroid: CGPoint?               // Local coordinates for labeling on map
    var centroidGlobal: CLLocationCoordinate2D?  // Global lat/lng for map overlay
    var polygon: [CGPoint]?              // Local coordinate room shape
    var polygonGlobal: [CLLocationCoordinate2D]? // Global coordinate room shape
    var metadata: [String: String]?      // Department, restrictions, Opening hours, Holidays, etc.
}

enum RoomType: String, Codable {
    case classroom
    case office
    case meetingRoom
    case restroom
    case restaurant
    case shop
    case exhibit
    case gate
    case ward
    case storage
    case hallway
    case other
    case exit
    case entrance
}

// Points of Interest
struct POI: Identifiable, Codable {
    let id: String
    var name: String
    var category: POICategory
    var position: CGPoint?               // (x,y) in local floor coordinate system
    var metadata: [String: String]?
}

// to review
enum POICategory: String, Codable {
    case elevator
    case escalator
    case stairs
    case entrance
    case exit
    case emergencyExit
    case infoDesk
    case wifi
    case charging
    case restroom
    case atm
    case security
    case other
}

struct FloorGeometry: Codable {
    var walkablePolygons: [[CGPoint]]?       // Areas you can walk in
    var obstacles: [[CGPoint]]?              // Walls, blocked zones
    var navigationGraph: NavigationGraph?    // Optional graph for pathfinding
}

struct NavigationGraph: Codable {
    var nodes: [NavNode]
    var edges: [NavEdge]
}

struct NavNode: Identifiable, Codable {
    let id: String
    var position: CGPoint
}

struct NavEdge: Identifiable, Codable {
    let id: String
    let from: String     // node ID
    let to: String       // node ID
    var distance: Double
}
