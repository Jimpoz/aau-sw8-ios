//
//  FloorPlanView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI
import MapKit
import CoreLocation

struct FloorPlanView: View {
    @StateObject private var vm = FloorPlanViewModel()
    @StateObject private var floorService = FloorPlanService()
    @State private var searchText = ""
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var locationManager = CLLocationManager()
    @State private var showFloorOverlay = false
    @State private var currentBuildingId: String?
    
    var body: some View {
        ZStack {
            Color.gray.opacity(0.05).ignoresSafeArea()
            
            // Apple Maps Layer (background)
            if let userLoc = userLocation {
                MapViewWithOverlay(
                    coordinate: userLoc,
                    showFloorOverlay: $showFloorOverlay,
                    rooms: floorService.rooms,
                    onBuildingZoom: { buildingId in
                        self.currentBuildingId = buildingId
                        self.showFloorOverlay = true
                        // Load floor data for the building
                        if let buildingId = buildingId {
                            loadBuildingFloorData(buildingId: buildingId)
                        }
                    },
                    onZoomOut: {
                        self.showFloorOverlay = false
                        self.currentBuildingId = nil
                    }
                )
                .ignoresSafeArea()
            }
            
            // Loading indicator
            if floorService.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            }
            
            DottedBackground().opacity(0.4)

            // Right-aligned Floor Switcher (only when overlay is active)
            if showFloorOverlay {
                VStack {
                    FloorSwitcher(
                        labels: floorLabels(),
                        selectedLabel: selectedLabel(),
                        onSelect: selectLabel(_:)
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
            }

            // Zoom controls
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZoomControls(zoomIn: {}, zoomOut: {})
                }
                .padding(.leading, 16)
                .padding(.bottom, 120)
            }
        }
        
        .safeAreaInset(edge: .top) {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.white.opacity(0.98), Color.white.opacity(0.0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 80)

                SearchBar(text: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        
        .safeAreaInset(edge: .bottom) {
            BottomRouteCard(
                title: "Gate A12",
                subtitle: "Level 2 • 5 min walk",
                chips: ["Start", "Elevator to L2", "Turn Right"]
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        
        .navigationTitle("Floor Plan")
        .onAppear {
            setupFloorData()
            requestUserLocation()
        }
        .onChange(of: vm.selectedFloor) { _ in
            if showFloorOverlay, let buildingId = currentBuildingId {
                loadBuildingFloorData(buildingId: buildingId)
            }
        }
    }
    
    private func setupFloorData() {
        if PreviewSupport.isRunning {
            vm.availableFloorLabels = ["L1", "L2", "L3", "G", "B1"]
            vm.selectedFloor = 1
        }
    }
    
    private func loadFloorGeometry() {
        let floorId = "floor_\(vm.selectedFloor)"
        Task {
            await floorService.fetchFloorGeometry(floorId: floorId)
        }
    }
    
    private func loadBuildingFloorData(buildingId: String) {
        // Construct floor ID based on building and selected floor
        let floorId = "\(buildingId)_floor_\(vm.selectedFloor)"
        Task {
            await floorService.fetchFloorGeometry(floorId: floorId)
        }
    }
    
    private func requestUserLocation() {
        locationManager.requestWhenInUseAuthorization()
        
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
           locationManager.authorizationStatus == .authorizedAlways {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let location = locationManager.location?.coordinate {
                    self.userLocation = location
                }
            }
        }
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
    let onBuildingZoom: (String?) -> Void
    let onZoomOut: () -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.isRotateEnabled = true
        mapView.mapType = .standard
        mapView.delegate = context.coordinator
        
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(region, animated: false)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Set initial region only once — avoids fighting user pan/zoom
        if !context.coordinator.initialRegionSet {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            uiView.setRegion(region, animated: false)
            context.coordinator.initialRegionSet = true
        }

        // Rebuild overlays whenever rooms or showFloorOverlay changes
        uiView.removeOverlays(uiView.overlays)

        if showFloorOverlay && !rooms.isEmpty {
            let overlays = buildOverlays(for: rooms)
            uiView.addOverlays(overlays, level: .aboveRoads)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func buildOverlays(for rooms: [Room]) -> [MKOverlay] {
        var overlays: [MKOverlay] = []

        // Dimmer: large dark polygon that fades out the world outside the building
        var dimmerCoords = dimmerPolygonCoords()
        let dimmer = MKPolygon(coordinates: &dimmerCoords, count: dimmerCoords.count)
        dimmer.title = "dimmer"
        overlays.append(dimmer)

        // One MKPolygon per room using polygon_global coordinates from backend
        for room in rooms {
            guard var coords = room.polygonGlobal, coords.count >= 3 else { continue }
            let polygon = MKPolygon(coordinates: &coords, count: coords.count)
            polygon.title = room.type.rawValue
            polygon.subtitle = room.name
            overlays.append(polygon)
        }

        return overlays
    }

    private func dimmerPolygonCoords() -> [CLLocationCoordinate2D] {
        // 0.5-degree box around AAU CPH — covers the full visible map when zoomed in
        let d = 0.5
        return [
            CLLocationCoordinate2D(latitude: 55.6588 + d, longitude: 12.5055 - d),
            CLLocationCoordinate2D(latitude: 55.6588 + d, longitude: 12.5055 + d),
            CLLocationCoordinate2D(latitude: 55.6588 - d, longitude: 12.5055 + d),
            CLLocationCoordinate2D(latitude: 55.6588 - d, longitude: 12.5055 - d),
        ]
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWithOverlay
        var initialRegionSet = false

        init(_ parent: MapViewWithOverlay) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let span = mapView.region.span
            let zoomLevel = span.latitudeDelta
            
            // Detect building-level zoom (latitudeDelta < 0.003 ≈ ~300 m visible)
            if zoomLevel < 0.003 {
                // AAU Copenhagen — A.C. Meyer Vænge 15
                let buildingLat = 55.6588
                let buildingLng = 12.5055
                let buildingLocation = CLLocation(latitude: buildingLat, longitude: buildingLng)
                let mapCenter = CLLocation(latitude: mapView.centerCoordinate.latitude,
                                           longitude: mapView.centerCoordinate.longitude)

                let distance = buildingLocation.distance(from: mapCenter)
                if distance < 200 { // Within 200 m of building
                    parent.onBuildingZoom("building_acm15")
                } else {
                    parent.onZoomOut()
                }
            } else {
                parent.onZoomOut()
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                if polygon.title == "dimmer" {
                    renderer.fillColor = UIColor.black.withAlphaComponent(0.35)
                    renderer.strokeColor = .clear
                    renderer.lineWidth = 0
                } else {
                    let color = uiColorForRoomType(polygon.title ?? "")
                    renderer.fillColor = color.withAlphaComponent(0.65)
                    renderer.strokeColor = color.withAlphaComponent(0.9)
                    renderer.lineWidth = 1.5
                }
                return renderer
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

// MARK: - Floor Plan Overlay Classes

class FloorPlanOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    
    init(coordinate: CLLocationCoordinate2D, boundingMapRect: MKMapRect) {
        self.coordinate = coordinate
        self.boundingMapRect = boundingMapRect
    }
}

class FloorPlanOverlayRenderer: MKOverlayRenderer {
    let rooms: [Room]
    
    init(overlay: MKOverlay, rooms: [Room]) {
        self.rooms = rooms
        super.init(overlay: overlay)
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // Draw floor plan rooms as overlay on the map
        for room in rooms {
            guard let polygon = room.polygon, polygon.count > 2 else { continue }
            
            // Convert room coordinates to map points
            // This would need coordinate transformation from floor plan to lat/lng
            // For now, we'll skip the actual drawing implementation
        }
    }
}

// MARK: - Floor Plan Overlay Renderer (SwiftUI)

struct FloorPlanOverlayView: View {
    let rooms: [Room]
    let userLocation: CGPoint?
    
    var body: some View {
        Canvas { context, size in
            // Draw rooms with semi-transparent overlay effect
            for room in rooms {
                drawRoomOverlay(room: room, in: &context)
            }
            
            // Draw user location
            if let userLoc = userLocation {
                drawUserLocationOverlay(at: userLoc, in: &context)
            }
        }
        .opacity(0.8) // Make it semi-transparent to show map underneath
    }
    
    private func drawRoomOverlay(room: Room, in context: inout GraphicsContext) {
        guard let polygon = room.polygon, polygon.count > 2 else { return }
        
        var path = Path()
        let firstPoint = polygon[0]
        path.move(to: firstPoint)
        
        for i in 1..<polygon.count {
            let point = polygon[i]
            path.addLine(to: point)
        }
        path.closeSubpath()
        
        let fillColor = colorForRoomType(room.type.rawValue)
        context.fill(path, with: .color(fillColor.opacity(0.5)))
        context.stroke(path, with: .color(fillColor), lineWidth: 3)
    }
    
    private func drawUserLocationOverlay(at point: CGPoint, in context: inout GraphicsContext) {
        let transformedPoint = CGPoint(x: point.x * 10, y: point.y * 10)
        
        var circlePath = Path()
        circlePath.addEllipse(in: CGRect(
            x: transformedPoint.x - 10,
            y: transformedPoint.y - 10,
            width: 20,
            height: 20
        ))
        
        context.fill(circlePath, with: .color(Color.blue.opacity(0.7)))
        context.stroke(circlePath, with: .color(.blue), lineWidth: 2)
    }
    
    private func colorForRoomType(_ type: String) -> Color {
        switch type {
        case "classroom": return .green
        case "hallway": return .gray
        case "restroom": return .blue
        case "entrance": return .orange
        case "exit": return .red
        default: return .purple
        }
    }
}

private struct SearchBar: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search..", text: $text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.black)
                .textInputAutocapitalization(.words)
            Divider().frame(height: 20).background(Color.gray.opacity(0.3))
            Button(action: {
                //to add the navigation function here
                print("Tapped")
            }) {
                Image(systemName: "location.north.line")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
                    .padding(8)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

private struct FloorSwitcher: View {
    let labels: [String]
    let selectedLabel: String?
    var onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Button(action: { onSelect(label) }) {
                    Text(label)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(isSelected(label) ? .white : .gray)
                        .frame(width: 44, height: 44)
                        .background(
                            isSelected(label) ? Color.blue : Color.white.opacity(0.92)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(Color.gray.opacity(0.2), lineWidth: isSelected(label) ? 0 : 1)
                        )
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
        .overlay(
            Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private func isSelected(_ label: String) -> Bool {
        selectedLabel == label
    }
}

private struct ZoomControls: View {
    var zoomIn: () -> Void
    var zoomOut: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.gray)
                    .padding(10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.gray)
                    .padding(10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

private struct BottomRouteCard: View {
    let title: String
    let subtitle: String
    let chips: [String]
    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color.gray.opacity(0.3)).frame(width: 44, height: 5).opacity(0.8)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(subtitle).font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
                    }
                }
                Spacer()
                Button(action: {
                    
                }) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.blue, in: Circle())
                        .shadow(color: Color.blue.opacity(0.35), radius: 10, x: 0, y: 6)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { c in
                        Text(c)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.vertical, 8).padding(.horizontal, 12)
                            .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
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
