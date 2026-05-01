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
                    Button {
                        if let lat = building.origin_lat, let lng = building.origin_lng {
                            mapNav.pendingBuildingCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                        } else {
                            mapNav.pendingBuildingCoordinate = nil
                        }
                        mapNav.pendingBuildingId = building.id
                        mapNav.selectedTab = .floorPlan
                    } label: {
                        BuildingRow(building: building)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct BuildingRow: View {
    let building: BuildingDTO

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue100)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "building.columns.fill")
                        .foregroundStyle(Color.blue600)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(building.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.slate800)
                let parts: [String] = [
                    building.short_name.map { "Code \($0)" },
                    building.address,
                    building.floor_count.map { "\($0) floor\($0 == 1 ? "" : "s")" }
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.slate500)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "location.north.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.blue600)
                .padding(10)
                .background(Color.blue50, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.slate100))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Building Floor Plan Viewer (view-mode)

private struct BuildingFloorPlanViewer: View {
    let building: BuildingDTO

    @StateObject private var service = FloorPlanService()
    @State private var floors: [FloorSummary] = []
    @State private var selectedFloorIdx: Int = 0
    @State private var selectedRoom: Room?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color.slate50.ignoresSafeArea()

                if service.isLoading && service.rooms.isEmpty {
                    ProgressView("Loading floor plan…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.rooms.isEmpty {
                    emptyState
                } else {
                    FloorPlanInteractive(
                        rooms: service.rooms,
                        onSelect: { selectedRoom = $0 }
                    )
                    .padding(16)
                }

                if floors.count > 1 {
                    floorSwitcher
                        .padding(.top, 16)
                        .padding(.trailing, 12)
                }
            }
        }
        .navigationTitle(building.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let list = await service.fetchFloorList(buildingId: building.id)
            floors = list
            if !list.isEmpty {
                selectedFloorIdx = list.firstIndex(where: { $0.floorIndex == 0 }) ?? 0
                if let id = activeFloorId() {
                    await service.fetchFloorGeometry(floorId: id)
                }
            }
        }
        .onChange(of: selectedFloorIdx) { _ in
            guard let id = activeFloorId() else { return }
            Task { await service.fetchFloorGeometry(floorId: id) }
        }
        .sheet(item: $selectedRoom) { room in
            RoomDetailSheet(room: room)
                .presentationDetents([.fraction(0.3), .medium])
        }
    }

    private func activeFloorId() -> String? {
        guard floors.indices.contains(selectedFloorIdx) else { return nil }
        return floors[selectedFloorIdx].id
    }

    private var floorSwitcher: some View {
        VStack(spacing: 6) {
            ForEach(floors.indices, id: \.self) { idx in
                Button {
                    selectedFloorIdx = idx
                } label: {
                    Text(floorLabel(floors[idx]))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(idx == selectedFloorIdx ? .white : .gray)
                        .frame(width: 44, height: 44)
                        .background(idx == selectedFloorIdx ? Color.blue : Color.white.opacity(0.95))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: idx == selectedFloorIdx ? 0 : 1))
                        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }

    private func floorLabel(_ summary: FloorSummary) -> String {
        if let name = summary.displayName, !name.isEmpty { return name }
        return summary.floorIndex >= 0 ? "F\(summary.floorIndex)" : "B\(-summary.floorIndex)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28))
                .foregroundStyle(Color.slate500)
            Text("No floor plan available")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.slate600)
            if let err = service.error {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FloorPlanInteractive: View {
    let rooms: [Room]
    let onSelect: (Room) -> Void

    var body: some View {
        GeometryReader { geo in
            let drawables = rooms.compactMap { r -> (Room, [CGPoint])? in
                guard let poly = r.polygon, poly.count >= 3 else { return nil }
                return (r, poly)
            }
            let bounds = unionBounds(drawables.map { $0.1 })

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)

                if let bounds {
                    let scale = fitScale(bounds: bounds, into: geo.size)
                    let offset = centerOffset(bounds: bounds, scale: scale, in: geo.size)

                    Canvas { ctx, _ in
                        for (room, polygon) in drawables {
                            let path = polygonPath(polygon, bounds: bounds, scale: scale, offset: offset, viewSize: geo.size)
                            ctx.fill(path, with: .color(fillColor(for: room.type)))
                            ctx.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 1.2)
                            if let centroid = room.centroid {
                                let p = transform(centroid, bounds: bounds, scale: scale, offset: offset, viewSize: geo.size)
                                ctx.draw(
                                    Text(room.name)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.8)),
                                    at: p
                                )
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        for (room, polygon) in drawables.reversed() {
                            let path = polygonPath(polygon, bounds: bounds, scale: scale, offset: offset, viewSize: geo.size)
                            if path.contains(location) {
                                onSelect(room)
                                return
                            }
                        }
                    }
                }
            }
        }
    }

    private func unionBounds(_ polygons: [[CGPoint]]) -> CGRect? {
        guard let first = polygons.first?.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for poly in polygons {
            for p in poly {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
        }
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    private func fitScale(bounds: CGRect, into size: CGSize) -> CGFloat {
        let pad: CGFloat = 24
        let avail = CGSize(width: max(size.width - pad * 2, 1), height: max(size.height - pad * 2, 1))
        return min(avail.width / bounds.width, avail.height / bounds.height)
    }

    private func centerOffset(bounds: CGRect, scale: CGFloat, in size: CGSize) -> CGPoint {
        let scaledW = bounds.width * scale
        let scaledH = bounds.height * scale
        return CGPoint(x: (size.width - scaledW) / 2, y: (size.height - scaledH) / 2)
    }

    private func transform(_ p: CGPoint, bounds: CGRect, scale: CGFloat, offset: CGPoint, viewSize: CGSize) -> CGPoint {
        let nx = (p.x - bounds.minX) * scale + offset.x
        let ny = (p.y - bounds.minY) * scale + offset.y
        return CGPoint(x: nx, y: viewSize.height - ny)
    }

    private func polygonPath(_ polygon: [CGPoint], bounds: CGRect, scale: CGFloat, offset: CGPoint, viewSize: CGSize) -> Path {
        var path = Path()
        let pts = polygon.map { transform($0, bounds: bounds, scale: scale, offset: offset, viewSize: viewSize) }
        guard let head = pts.first else { return path }
        path.move(to: head)
        for p in pts.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    private func fillColor(for type: RoomType) -> Color {
        switch type {
        case .classroom:   return Color(red: 0.85, green: 0.95, blue: 0.85)
        case .office:      return Color(red: 0.85, green: 0.92, blue: 1.0)
        case .meetingRoom: return Color(red: 0.92, green: 0.85, blue: 1.0)
        case .restroom:    return Color(red: 0.85, green: 0.97, blue: 1.0)
        case .restaurant:  return Color(red: 1.0, green: 0.92, blue: 0.78)
        case .shop:        return Color(red: 1.0, green: 0.86, blue: 0.86)
        case .hallway:     return Color(red: 0.94, green: 0.94, blue: 0.94)
        case .entrance:    return Color(red: 1.0, green: 0.86, blue: 0.66)
        case .exit:        return Color(red: 1.0, green: 0.78, blue: 0.78)
        default:           return Color(red: 0.97, green: 0.97, blue: 0.99)
        }
    }
}

private struct RoomDetailSheet: View {
    let room: Room

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .font(.system(size: 20, weight: .bold))
                    Text(prettyType(room.type))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: iconName(for: room.type))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.blue)
                    .padding(10)
                    .background(Color.blue.opacity(0.12), in: Circle())
            }
            if let centroid = room.centroid {
                HStack(spacing: 6) {
                    Image(systemName: "location")
                        .font(.system(size: 12))
                    Text(String(format: "x %.1f m · y %.1f m", centroid.x, centroid.y))
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private func prettyType(_ type: RoomType) -> String {
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

    private func iconName(for type: RoomType) -> String {
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

#Preview("Explore") { ExploreView().environmentObject(AuthService()) }
