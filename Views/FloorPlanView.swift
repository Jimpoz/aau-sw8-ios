//
//  FloorPlanView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

final class MapActionProxy: ObservableObject {
    weak var mapView: MKMapView?
    var lastProgrammaticFly: Date? = nil

    func zoomIn() {
        guard let mv = mapView else { return }
        var r = mv.region
        r.span.latitudeDelta  = max(r.span.latitudeDelta  / 2, 0.0001)
        r.span.longitudeDelta = max(r.span.longitudeDelta / 2, 0.0001)
        mv.setRegion(r, animated: true)
    }

    func zoomOut() {
        guard let mv = mapView else { return }
        var r = mv.region
        r.span.latitudeDelta  = min(r.span.latitudeDelta  * 2, 90)
        r.span.longitudeDelta = min(r.span.longitudeDelta * 2, 90)
        mv.setRegion(r, animated: true)
    }

    func centerOnUser() {
        guard let mv = mapView,
              let coord = mv.userLocation.location?.coordinate else { return }
        mv.setCenter(coord, animated: true)
    }

    func flyTo(_ coordinate: CLLocationCoordinate2D) {
        guard let mv = mapView else { return }
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
        )
        mv.setRegion(region, animated: true)
        lastProgrammaticFly = Date()
    }
}

struct RouteDestination {
    let title: String
    let subtitle: String
    let steps: [String]
}

struct FloorPlanView: View {
    @EnvironmentObject private var mapNav: MapNavigationCoordinator
    @StateObject private var vm          = FloorPlanViewModel()
    @StateObject private var floorService = FloorPlanService()
    @StateObject private var mapProxy    = MapActionProxy()
    @StateObject private var assistant   = AssistantService()
    @StateObject private var locationManager = LocationManager()

    @State private var searchText        = ""
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var locationAccuracy: Double?
    @State private var showFloorOverlay  = false
    @State private var currentBuildingId: String?
    @State private var routeDestination: RouteDestination?
    @State private var isAskingForDirections = false
    @State private var directionsPrompt = ""
    @State private var isResolvingRoute = false

    var body: some View {
        ZStack {
            Color.gray.opacity(0.05).ignoresSafeArea()

            MapViewWithOverlay(
                coordinate: userLocation ?? CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683),
                showFloorOverlay: $showFloorOverlay,
                rooms: floorService.rooms,
                buildings: floorService.buildings,
                actionProxy: mapProxy,
                onBuildingZoom: { buildingId in
                    let changedBuilding = (buildingId != self.currentBuildingId)
                    self.currentBuildingId = buildingId
                    self.showFloorOverlay  = true
                    if let buildingId {
                        if changedBuilding {
                            loadFloorsAndOverlay(buildingId: buildingId)
                        } else {
                            loadBuildingFloorData(buildingId: buildingId)
                        }
                    }
                },
                onZoomOut: {
                    self.showFloorOverlay  = false
                    self.currentBuildingId = nil
                }
            )
            .ignoresSafeArea()

            if floorService.isLoading {
                ProgressView().scaleEffect(1.5)
            }

            DottedBackground().opacity(0.4).allowsHitTesting(false)

            if showFloorOverlay {
                VStack {
                    FloorSwitcher(
                        labels: floorLabels(),
                        selectedLabel: selectedLabel(),
                        onSelect: selectLabel
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
            }
        }

        .safeAreaInset(edge: .top) {
            VStack(spacing: 6) {
                SearchBar(text: $searchText, onSearch: handleSearch)
                    .padding(.horizontal, 16)

                HStack(alignment: .center) {
                    LocationTypePill(
                        label: locationTypeLabel,
                        icon:  locationTypeIcon
                    )

                    Spacer()

                    ZoomControls(
                        zoomIn:  { mapProxy.zoomIn()  },
                        zoomOut: { mapProxy.zoomOut() }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            .padding(.top, 8)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.98), Color.white.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }

        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        directionsPrompt = ""
                        isAskingForDirections = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "signpost.right.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Directions")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Color.blue, in: Capsule())
                        .shadow(color: Color.blue.opacity(0.35), radius: 10, x: 0, y: 6)
                    }
                    .padding(.leading, 16)

                    Spacer()

                    Button { mapProxy.centerOnUser() } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Color.blue, in: Circle())
                            .shadow(color: Color.blue.opacity(0.35), radius: 10, x: 0, y: 6)
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom,8)

                if let dest = routeDestination {
                    BottomRouteCard(destination: dest) {
                        routeDestination = nil
                        searchText = ""
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }

        .navigationTitle("Floor Plan")
        .alert("Get directions", isPresented: $isAskingForDirections) {
            TextField("e.g. A101, Cafeteria, Library", text: $directionsPrompt)
            Button("Go") { askForDirections() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Type where you want to go. The assistant will produce step-by-step directions from your current location.")
        }
        .onAppear {
            setupFloorData()
            requestUserLocation()
            if floorService.buildings.isEmpty {
                Task {
                    await floorService.fetchVisibleBuildings()
                    consumePendingBuildingTarget()
                }
            } else {
                consumePendingBuildingTarget()
            }
        }
        .onChange(of: vm.selectedFloor) { _ in
            if showFloorOverlay, let buildingId = currentBuildingId {
                loadBuildingFloorData(buildingId: buildingId)
            }
        }
        .onChange(of: mapNav.pendingBuildingId) { _ in consumePendingBuildingTarget() }
        .onChange(of: floorService.buildings.count) { _ in consumePendingBuildingTarget() }
        .onReceive(locationManager.$lastLocation) { _ in syncFromLocationManager() }
        .onReceive(locationManager.$horizontalAccuracyMeters) { _ in syncFromLocationManager() }
    }

    private func consumePendingBuildingTarget() {
        guard let pending = mapNav.pendingBuildingId else { return }
        guard let building = floorService.buildings.first(where: { $0.id == pending }) else {
            print("[NAV] pending building \(pending) not yet in locators (count=\(floorService.buildings.count)), waiting…")
            return
        }
        print("[NAV] flying to building \(building.name) at \(building.coordinate) and loading floors directly")
        mapProxy.flyTo(building.coordinate)
        currentBuildingId = pending
        showFloorOverlay = true
        loadFloorsAndOverlay(buildingId: pending)
        mapNav.pendingBuildingId = nil
    }

    private func askForDirections() {
        let dest = directionsPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dest.isEmpty else { return }
        searchText = dest
        resolveRoute(to: dest)
    }

    private func resolveRoute(to destination: String) {
        routeDestination = RouteDestination(title: destination, subtitle: "Calculating route…", steps: [])
        isResolvingRoute = true

        var context: [String: Any] = [:]
        if let loc = userLocation {
            context["x"] = loc.longitude
            context["y"] = loc.latitude
        }

        Task {
            do {
                let answer = try await assistant.send(
                    userText: "Give me step-by-step directions to \(destination) from my current location.",
                    context: context
                )
                let steps = answer
                    .split(whereSeparator: { "\n•".contains($0) })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                await MainActor.run {
                    routeDestination = RouteDestination(
                        title: destination,
                        subtitle: steps.isEmpty ? answer : "Route ready",
                        steps: steps.isEmpty ? [answer] : steps
                    )
                    isResolvingRoute = false
                }
            } catch {
                await MainActor.run {
                    routeDestination = RouteDestination(
                        title: destination,
                        subtitle: "Could not compute route",
                        steps: [error.localizedDescription]
                    )
                    isResolvingRoute = false
                }
            }
        }
    }

    private func setupFloorData() {
        if PreviewSupport.isRunning {
            vm.availableFloorLabels = ["L1", "L2", "L3", "G", "B1"]
            vm.selectedFloor = 1
        }
    }

    private func loadFloorsAndOverlay(buildingId: String) {
        Task {
            let summaries = await floorService.fetchFloorList(buildingId: buildingId)
            await MainActor.run {
                vm.availableFloors = summaries.map { $0.floorIndex }
                vm.availableFloorLabels = summaries.map { floorLabel(for: $0) }
                if !summaries.isEmpty {
                    let groundIndex = summaries.firstIndex { $0.floorIndex == 0 } ?? 0
                    vm.selectedFloor = groundIndex
                }
            }
            if let active = activeFloorId(in: summaries) {
                await floorService.fetchFloorGeometry(floorId: active)
            }
        }
    }

    private func loadBuildingFloorData(buildingId: String) {
        guard let floorId = activeFloorId(in: floorService.floors) else { return }
        Task { await floorService.fetchFloorGeometry(floorId: floorId) }
    }

    private func activeFloorId(in summaries: [FloorSummary]) -> String? {
        guard !summaries.isEmpty else { return nil }
        let idx = summaries.indices.contains(vm.selectedFloor) ? vm.selectedFloor : 0
        return summaries[idx].id
    }

    private func floorLabel(for summary: FloorSummary) -> String {
        if let name = summary.displayName, !name.isEmpty { return name }
        return summary.floorIndex >= 0 ? "F\(summary.floorIndex)" : "B\(-summary.floorIndex)"
    }

    private func requestUserLocation() {
        locationManager.requestPermission()
        if let location = locationManager.lastLocation {
            userLocation = location.coordinate
            locationAccuracy = location.horizontalAccuracy
        }
    }

    private func syncFromLocationManager() {
        if let loc = locationManager.lastLocation {
            userLocation = loc.coordinate
        }
        locationAccuracy = locationManager.horizontalAccuracyMeters
    }

    private func handleSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        resolveRoute(to: q)
    }


    private var locationTypeLabel: String {
        guard let acc = locationAccuracy, acc >= 0 else { return "Locating…" }
        if acc < 10  { return "GPS + BLE" }
        if acc < 30  { return "GPS" }
        if acc < 100 { return "GPS + WiFi" }
        return "Network"
    }

    private var locationTypeIcon: String {
        guard let acc = locationAccuracy, acc >= 0 else { return "location.slash.fill" }
        if acc < 30  { return "location.fill" }
        if acc < 100 { return "wifi" }
        return "antenna.radiowaves.left.and.right"
    }


    private func floorLabels() -> [String] {
        if let labels = vm.availableFloorLabels { return labels }
        return vm.availableFloors.map { "F\($0)" }
    }

    private func selectedLabel() -> String? {
        if let labels = vm.availableFloorLabels {
            return labels.indices.contains(vm.selectedFloor) ? labels[vm.selectedFloor] : labels.first
        }
        return "F\(vm.selectedFloor)"
    }

    private func selectLabel(_ label: String) {
        if let labels = vm.availableFloorLabels, let idx = labels.firstIndex(of: label) {
            vm.selectedFloor = idx
        }
    }
}

// MARK: - Map View with Overlay

struct MapViewWithOverlay: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    @Binding var showFloorOverlay: Bool
    let rooms: [Room]
    let buildings: [BuildingLocator]
    let actionProxy: MapActionProxy
    let onBuildingZoom: (String?) -> Void
    let onZoomOut: () -> Void

    private static let indoorZoomThreshold = 0.003
    private static let buildingProximityMeters: CLLocationDistance = 200

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation   = true
        mapView.userTrackingMode    = .follow
        mapView.isRotateEnabled     = true
        mapView.mapType             = .standard
        mapView.delegate            = context.coordinator

        actionProxy.mapView = mapView

        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self
        if actionProxy.mapView == nil { actionProxy.mapView = uiView }
        if !context.coordinator.initialRegionSet {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            uiView.setRegion(region, animated: false)
            context.coordinator.initialRegionSet = true
        }

        uiView.removeOverlays(uiView.overlays)
        let polygons = buildOverlays(for: rooms)
        let withGlobal = rooms.filter { ($0.polygonGlobal?.count ?? 0) >= 3 }.count
        print("[OVERLAY] showFloorOverlay=\(showFloorOverlay) rooms=\(rooms.count) withPolygonGlobal=\(withGlobal) → addOverlays=\(polygons.count)")
        if showFloorOverlay && !polygons.isEmpty {
            uiView.addOverlays(polygons, level: .aboveLabels)
            if let first = polygons.first as? MKPolygon {
                let rect = polygons.reduce(first.boundingMapRect) { $0.union($1.boundingMapRect) }
                let padded = rect.insetBy(dx: -rect.size.width * 0.4, dy: -rect.size.height * 0.4)
                if !uiView.visibleMapRect.contains(rect) {
                    print("[OVERLAY] visibleMapRect does not contain polygons; current span=\(uiView.region.span.latitudeDelta)")
                }
                _ = padded
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }


    private func buildOverlays(for rooms: [Room]) -> [MKOverlay] {
        var overlays: [MKOverlay] = []
        for room in rooms {
            guard var coords = room.polygonGlobal, coords.count >= 3 else { continue }
            let polygon = MKPolygon(coordinates: &coords, count: coords.count)
            polygon.title    = room.type.rawValue
            polygon.subtitle = room.name
            overlays.append(polygon)
        }
        return overlays
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWithOverlay
        var initialRegionSet = false

        init(_ parent: MapViewWithOverlay) { self.parent = parent }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let zoomLevel = mapView.region.span.latitudeDelta
            if let last = parent.actionProxy.lastProgrammaticFly {
                let elapsed = Date().timeIntervalSince(last)
                if elapsed < 0.6 && zoomLevel < MapViewWithOverlay.indoorZoomThreshold {
                    print("[PROX] ignoring proximity trigger due to recent programmatic fly (\(elapsed))")
                    return
                }
            }
            guard zoomLevel < MapViewWithOverlay.indoorZoomThreshold else {
                print("[PROX] zoom=\(zoomLevel) above threshold → onZoomOut")
                parent.onZoomOut()
                return
            }
            let center = CLLocation(
                latitude: mapView.centerCoordinate.latitude,
                longitude: mapView.centerCoordinate.longitude
            )
            var nearest: (BuildingLocator, CLLocationDistance)? = nil
            for building in parent.buildings {
                let loc = CLLocation(
                    latitude: building.coordinate.latitude,
                    longitude: building.coordinate.longitude
                )
                let distance = center.distance(from: loc)
                if nearest == nil || distance < nearest!.1 {
                    nearest = (building, distance)
                }
            }
            if let (building, distance) = nearest,
               distance < MapViewWithOverlay.buildingProximityMeters {
                print("[PROX] zoom=\(zoomLevel) → \(building.name) at \(Int(distance))m, triggering overlay")
                parent.onBuildingZoom(building.id)
            } else {
                let nearestName = nearest?.0.name ?? "none"
                let nearestDist = nearest.map { Int($0.1) } ?? -1
                print("[PROX] zoom=\(zoomLevel) zoomed-in but nearest building \(nearestName) is \(nearestDist)m away — keeping current overlay state (not auto-clearing)")
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: polygon)
                let color = uiColorForRoomType(polygon.title ?? "")
                r.fillColor   = color.withAlphaComponent(0.75)
                r.strokeColor = color.withAlphaComponent(0.95)
                r.lineWidth   = 1.5
                return r
            }
            if let floorOverlay = overlay as? FloorPlanOverlay {
                return FloorPlanOverlayRenderer(overlay: floorOverlay, rooms: parent.rooms)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        private func uiColorForRoomType(_ type: String) -> UIColor {
            switch type {
            case "classroom":   return UIColor(red: 0.22, green: 0.72, blue: 0.42, alpha: 1)
            case "office":      return UIColor(red: 0.35, green: 0.60, blue: 0.90, alpha: 1)
            case "meetingRoom": return UIColor(red: 0.60, green: 0.40, blue: 0.90, alpha: 1)
            case "restroom":    return UIColor(red: 0.20, green: 0.70, blue: 0.90, alpha: 1)
            case "restaurant":  return UIColor(red: 1.00, green: 0.78, blue: 0.20, alpha: 1)
            case "shop":        return UIColor(red: 1.00, green: 0.50, blue: 0.50, alpha: 1)
            case "entrance":    return UIColor(red: 1.00, green: 0.62, blue: 0.22, alpha: 1)
            case "exit":        return UIColor(red: 0.90, green: 0.28, blue: 0.28, alpha: 1)
            case "hallway":     return UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)
            default:            return UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1)
            }
        }
    }
}


class FloorPlanOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    init(coordinate: CLLocationCoordinate2D, boundingMapRect: MKMapRect) {
        self.coordinate      = coordinate
        self.boundingMapRect = boundingMapRect
    }
}

class FloorPlanOverlayRenderer: MKOverlayRenderer {
    let rooms: [Room]
    init(overlay: MKOverlay, rooms: [Room]) {
        self.rooms = rooms
        super.init(overlay: overlay)
    }
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {}
}


private struct SearchBar: View {
    @Binding var text: String
    var onSearch: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)

            TextField("Search destinations…", text: $text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.black)
                .textInputAutocapitalization(.words)
                .onSubmit { onSearch(text) }

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray.opacity(0.6))
                }
            }

            Divider().frame(height: 20).background(Color.gray.opacity(0.3))

            Button { onSearch(text) } label: {
                Image(systemName: "location.north.line")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
                    .padding(8)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

private struct LocationTypePill: View {
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.blue)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
    }
}

private struct FloorSwitcher: View {
    let labels: [String]
    let selectedLabel: String?
    var onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Button { onSelect(label) } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(isSelected(label) ? .white : .gray)
                        .frame(width: 44, height: 44)
                        .background(isSelected(label) ? Color.blue : Color.white.opacity(0.92))
                        .overlay(RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.gray.opacity(0.2), lineWidth: isSelected(label) ? 0 : 1))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(isSelected(label) ? 0.18 : 0.06),
                                radius: isSelected(label) ? 8 : 4, x: 0, y: 4)
                        .scaleEffect(isSelected(label) ? 1.08 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.9), in: Capsule())
        .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private func isSelected(_ label: String) -> Bool { selectedLabel == label }
}

private struct ZoomControls: View {
    var zoomIn:  () -> Void
    var zoomOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: zoomIn) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 42, height: 42)
            }
            Divider().frame(width: 30)
            Button(action: zoomOut) {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 42, height: 42)
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

private struct BottomRouteCard: View {
    let destination: RouteDestination
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Capsule().fill(Color.gray.opacity(0.3)).frame(width: 44, height: 5)
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(8)
                            .background(Color.gray.opacity(0.12), in: Circle())
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(destination.subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                Button {} label: {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.blue, in: Circle())
                        .shadow(color: Color.blue.opacity(0.35), radius: 10, x: 0, y: 6)
                }
            }

            if !destination.steps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(destination.steps, id: \.self) { step in
                            Text(step)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.vertical, 8).padding(.horizontal, 12)
                                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.gray.opacity(0.2)))
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 12)
    }
}

#Preview("Floor Plan") { FloorPlanView() }
