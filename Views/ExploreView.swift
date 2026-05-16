//
//  ExploreView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI
import CoreLocation

struct ExploreView: View {
    @State private var selectedCampus: VisibleCampusDTO?

    var body: some View {
        NavigationStack {
            if let campus = selectedCampus {
                ExploreCampusView(campus: campus) {
                    selectedCampus = nil
                }
            } else {
                VisibleCampusPickerView(
                    title: "Explore",
                    subtitle: "Pick a campus to browse its buildings."
                ) { campus in
                    selectedCampus = campus
                }
            }
        }
    }
}

private struct ExploreCampusView: View {
    let campus: VisibleCampusDTO
    let onChangeCampus: () -> Void

    @StateObject private var orgs = OrganizationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if orgs.isLoading && orgs.buildings.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading buildings…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.slate500)
                    }
                    .padding(.horizontal, 16)
                }

                if let err = orgs.errorText {
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                }

                campusSection
                buildingsSection
            }
            .padding(.bottom, 24)
        }
        .background(Color.slate50)
        .task { await orgs.loadBuildings(forCampus: campus.id) }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explore")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.slate800)
                if let orgName = campus.organization_name, !orgName.isEmpty {
                    Text(orgName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.slate500)
                } else if campus.is_public {
                    Text("Public location")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.slate500)
                }
            }
            Spacer()
            Button(action: onChangeCampus) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("Switch")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(Color.blue600, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var campusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Campus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.slate600)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue100)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "map.fill")
                            .foregroundStyle(Color.blue600)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(campus.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.slate800)
                    if let desc = campus.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.slate500)
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.slate100))
            .padding(.horizontal, 16)
        }
    }

    private var buildingsSection: some View {
        BuildingsSection(buildings: orgs.buildings, isLoading: orgs.isLoading, errorText: orgs.errorText)
    }
}

private struct DrillRow<Destination: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    @ViewBuilder let destination: () -> Destination
    let onNavigate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                destination()
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.blue100)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: icon)
                                .foregroundStyle(Color.blue600)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.slate800)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.slate500)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onNavigate) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.blue600)
                    .padding(10)
                    .background(Color.blue50, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.slate100))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

private struct BuildingsSection: View {
    let buildings: [BuildingDTO]
    let isLoading: Bool
    let errorText: String?

    @EnvironmentObject private var mapNav: MapNavigationCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Buildings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.slate600)
                Spacer()
                Text("\(buildings.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.slate500)
            }
            .padding(.horizontal, 16)

            if !isLoading && buildings.isEmpty && errorText == nil {
                Text("This campus has no buildings yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.slate500)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 10) {
                ForEach(buildings) { building in
                    DrillRow(
                        title: building.name,
                        subtitle: buildingSubtitle(building),
                        icon: "building.columns.fill",
                        destination: { FloorsListView(building: building) },
                        onNavigate: { navigateToBuilding(building) }
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func navigateToBuilding(_ b: BuildingDTO) {
        if let lat = b.origin_lat, let lng = b.origin_lng {
            mapNav.pendingBuildingCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            mapNav.pendingBuildingCoordinate = nil
        }
        mapNav.pendingBuildingId = b.id
        mapNav.pendingBuildingName = b.name
        mapNav.selectedTab = .floorPlan
    }

    private func buildingSubtitle(_ b: BuildingDTO) -> String? {
        let parts: [String] = [
            b.short_name.map { "Code \($0)" },
            b.address,
            b.floor_count.map { "\($0) floor\($0 == 1 ? "" : "s")" }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Floors level

private struct FloorsListView: View {
    let building: BuildingDTO

    @StateObject private var service = FloorPlanService()
    @EnvironmentObject private var mapNav: MapNavigationCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if service.isLoading && service.floors.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading floors…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.slate500)
                    }
                    .padding(.horizontal, 16)
                }
                if !service.isLoading && service.floors.isEmpty {
                    Text("This building has no floors yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.slate500)
                        .padding(.horizontal, 16)
                }
                ForEach(service.floors) { floor in
                    DrillRow(
                        title: floorTitle(floor),
                        subtitle: floor.displayName == floorTitle(floor) ? nil : floor.displayName,
                        icon: "square.stack.3d.up.fill",
                        destination: { RoomsListView(building: building, floor: floor) },
                        onNavigate: { navigateToFloor(floor) }
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.slate50)
        .navigationTitle(building.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { _ = await service.fetchFloorList(buildingId: building.id) }
    }

    private func floorTitle(_ f: FloorSummary) -> String {
        if let n = f.displayName, !n.isEmpty { return n }
        if f.floorIndex == 0 { return "Ground floor" }
        return f.floorIndex > 0 ? "Floor \(f.floorIndex)" : "Basement \(-f.floorIndex)"
    }

    private func navigateToFloor(_ f: FloorSummary) {
        if let lat = building.origin_lat, let lng = building.origin_lng {
            mapNav.pendingBuildingCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            mapNav.pendingBuildingCoordinate = nil
        }
        mapNav.pendingBuildingId = building.id
        mapNav.pendingBuildingName = building.name
        mapNav.pendingFloorIndex = f.floorIndex
        mapNav.selectedTab = .floorPlan
    }
}

// MARK: - Rooms level

private struct RoomsListView: View {
    let building: BuildingDTO
    let floor: FloorSummary

    @StateObject private var service = FloorPlanService()
    @EnvironmentObject private var mapNav: MapNavigationCoordinator
    @State private var selectedType: RoomType?

    private var availableTypes: [RoomType] {
        let unique = Set(service.rooms.map { $0.type })
        return unique.sorted { roomTypeLabel($0) < roomTypeLabel($1) }
    }

    private var filteredRooms: [Room] {
        let base = selectedType.map { t in service.rooms.filter { $0.type == t } }
            ?? service.rooms
        return base.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if service.isLoading && service.rooms.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading rooms…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.slate500)
                    }
                    .padding(.horizontal, 16)
                }
                if !service.isLoading && service.rooms.isEmpty {
                    Text("No rooms on this floor.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.slate500)
                        .padding(.horizontal, 16)
                }
                if availableTypes.count > 1 {
                    typeFilterBar
                }
                if !service.rooms.isEmpty && filteredRooms.isEmpty {
                    Text("No rooms match this filter.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.slate500)
                        .padding(.horizontal, 16)
                }
                ForEach(filteredRooms) { room in
                    RoomRow(room: room, onNavigate: { navigateToRoom(room) })
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.slate50)
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.fetchFloorGeometry(floorId: floor.id) }
    }

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedType == nil) {
                    selectedType = nil
                }
                ForEach(availableTypes, id: \.self) { type in
                    FilterChip(label: roomTypeLabel(type), isSelected: selectedType == type) {
                        selectedType = (selectedType == type) ? nil : type
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var navTitle: String {
        if let n = floor.displayName, !n.isEmpty { return "\(building.name) · \(n)" }
        return building.name
    }

    private func navigateToRoom(_ room: Room) {
        if let lat = building.origin_lat, let lng = building.origin_lng {
            mapNav.pendingBuildingCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            mapNav.pendingBuildingCoordinate = nil
        }
        mapNav.pendingBuildingId = building.id
        mapNav.pendingBuildingName = building.name
        mapNav.pendingFloorIndex = floor.floorIndex

        let coord: CLLocationCoordinate2D? = room.centroidGlobal ?? {
            guard let p = room.polygonGlobal, !p.isEmpty else { return nil }
            let lat = p.reduce(0.0) { $0 + $1.latitude } / Double(p.count)
            let lng = p.reduce(0.0) { $0 + $1.longitude } / Double(p.count)
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }()
        mapNav.pendingDestinationSpaceId = room.id
        mapNav.pendingDestinationSpaceName = room.name
        mapNav.pendingDestinationSpaceCoordinate = coord
        mapNav.selectedTab = .floorPlan
    }
}

private struct RoomRow: View {
    let room: Room
    let onNavigate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue100)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: icon(for: room.type))
                        .foregroundStyle(Color.blue600)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.slate800)
                Text(roomTypeLabel(room.type))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.slate500)
            }
            Spacer()
            Button(action: onNavigate) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.blue600)
                    .padding(10)
                    .background(Color.blue50, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.slate100))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }

    private func icon(for type: RoomType) -> String {
        switch type {
        case .classroom:   return "graduationcap.fill"
        case .office:      return "briefcase.fill"
        case .meetingRoom: return "person.3.fill"
        case .restroom:    return "figure.dress.line.vertical.figure"
        case .restaurant:  return "fork.knife"
        case .shop:        return "bag.fill"
        case .hallway:     return "arrow.left.and.right"
        case .entrance:    return "door.left.hand.open"
        case .exit:        return "door.right.hand.open"
        default:           return "square.dashed"
        }
    }

}

private func roomTypeLabel(_ type: RoomType) -> String {
    switch type {
    case .classroom:   return "Classroom"
    case .office:      return "Office"
    case .meetingRoom: return "Meeting room"
    case .restroom:    return "Restroom"
    case .restaurant:  return "Cafeteria"
    case .shop:        return "Shop"
    case .hallway:     return "Corridor"
    case .entrance:    return "Entrance"
    case .exit:        return "Exit"
    default:           return "Space"
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : Color.slate700)
                .background(
                    Capsule().fill(isSelected ? Color.blue600 : Color.white)
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Color.slate200, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Explore") {
    ExploreView()
        .environmentObject(AuthService())
        .environmentObject(MapNavigationCoordinator())
}
