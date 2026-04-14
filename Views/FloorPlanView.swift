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
    
    var body: some View {
        ZStack {
            Color.gray.opacity(0.05).ignoresSafeArea()
            
            // Apple Maps Layer (background)
            if let userLoc = userLocation {
                MapView(coordinate: userLoc)
                    .ignoresSafeArea()
            }
            
            // Floor Plan Renderer (overlay)
            if !floorService.rooms.isEmpty {
                FloorPlanRenderer(
                    rooms: floorService.rooms,
                    userLocation: userLocation.map { CGPoint(x: CGFloat($0.latitude * 1000), y: CGFloat($0.longitude * 1000)) }
                )
                .ignoresSafeArea()
            } else if floorService.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            }
            
            DottedBackground().opacity(0.4)

            // Right-aligned Floor Switcher
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
            loadFloorGeometry()
        }
    }
    
    private func setupFloorData() {
        if PreviewSupport.isRunning {
            vm.availableFloorLabels = ["L1", "L2", "L3", "G", "B1"]
            vm.selectedFloor = 1
            loadFloorGeometry()
        }
    }
    
    private func loadFloorGeometry() {
        let floorId = "floor_\(vm.selectedFloor)"
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

// MARK: - Map View

struct MapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.isRotateEnabled = true
        mapView.mapType = .standard
        
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(region, animated: false)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        uiView.setRegion(region, animated: true)
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
