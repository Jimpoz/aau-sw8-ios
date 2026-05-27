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
import CoreMotion

final class NavigationMotionDetector: ObservableObject {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var lastMotionAt: Date?
    private var running = false

    private let accelerationThreshold: Double = 0.025
    private let motionTimeoutSeconds: Double = 1.5

    var isAvailable: Bool {
        return motion.isDeviceMotionAvailable
    }

    var isMoving: Bool {
        guard let last = lastMotionAt else { return false }
        return Date().timeIntervalSince(last) <= motionTimeoutSeconds
    }

    func start() {
        guard isAvailable, !running else { return }
        running = true
        lastMotionAt = nil
        queue.maxConcurrentOperationCount = 1
        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self = self, let d = data else { return }
            let ax = d.userAcceleration.x
            let ay = d.userAcceleration.y
            let az = d.userAcceleration.z
            let mag = (ax * ax + ay * ay + az * az).squareRoot()
            if mag > self.accelerationThreshold {
                self.lastMotionAt = Date()
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
        lastMotionAt = nil
    }
}

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

    func startFollowingUser() {
        guard let mv = mapView else { return }
        mv.userTrackingMode = .followWithHeading
    }

    func stopFollowingUser() {
        guard let mv = mapView else { return }
        mv.userTrackingMode = .none
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

enum BuildingEditScope {
    case building   // moves the whole building (every floor) rigidly
    case floor      // moves only the visible floor
}

struct BuildingEditState {
    let scope: BuildingEditScope
    let buildingId: String
    let floorId: String?            // set when scope == .floor
    let originLat: Double
    let originLng: Double
    let baseBearing: Double
    let baseScale: Double

    var deltaLat: Double = 0
    var deltaLng: Double = 0
    var deltaBearing: Double = 0      // degrees, additive
    var scaleMultiplier: Double = 1   // multiplicative

    var newOriginLat: Double { originLat + deltaLat }
    var newOriginLng: Double { originLng + deltaLng }
    var newBearing: Double { baseBearing + deltaBearing }
    var newScale: Double { baseScale * scaleMultiplier }
    var isDirty: Bool {
        deltaLat != 0 || deltaLng != 0 || deltaBearing != 0 || scaleMultiplier != 1
    }
}

struct FloorPlanView: View {
    @EnvironmentObject private var mapNav: MapNavigationCoordinator
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var diContainer: DIContainer
    @StateObject private var vm          = FloorPlanViewModel()
    @StateObject private var floorService = FloorPlanService()
    @StateObject private var mapProxy    = MapActionProxy()
    @StateObject private var assistant   = AssistantService()
    @StateObject private var navigationService = NavigationService()
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var walkedCoordinates: [CLLocationCoordinate2D] = []
    @StateObject private var locationManager = LocationManager()
    @StateObject private var barometer       = BarometerService()

    @State private var searchText        = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var locationAccuracy: Double?
    @State private var showSnapConfirmation = false
    @State private var showFloorOverlay  = false
    @State private var currentBuildingId: String?
    @State private var currentBuildingOrgId: String?
    @State private var currentBuildingCoordinate: CLLocationCoordinate2D?
    @State private var lastBuildingId: String?
    @State private var lastBuildingCoordinate: CLLocationCoordinate2D?
    @State private var visitedBuildings: [BuildingLocator] = []
    @State private var routeDestination: RouteDestination?
    @State private var pendingRouteSuggestion: SpaceSuggestion?
    @State private var isResolvingRoute = false
    @State private var isNavigating = false
    @State private var offRouteStreak = 0
    @State private var isRerouting = false
    @State private var userOnRouteFloor = false
    @State private var simulatedPosition: CLLocationCoordinate2D?
    @State private var simulatedArcLengthMeters: Double = 0
    @State private var lastSimulationTick: Date?
    @State private var simulationTimer: Timer?
    @State private var lastAnchoredForcedSpaceId: String?
    @State private var forcedSpaceFloorId: String?
    @State private var forcedSpaceFloorIndex: Int?
    /// Set to true once applyForcedLocationIfReady has successfully placed the
    /// user marker. While true, applyForcedLocationIfReady will NOT switch
    /// floors back — the user is free to browse other floors for routing.
    @State private var forcedSpaceHasAnchored: Bool = false
    @State private var arrivalBanner: String?
    @StateObject private var motionDetector = NavigationMotionDetector()
    private let averageWalkingSpeedMS: Double = 1.4
    private let arrivalRadiusMeters: Double = 5
    private let degradedAccuracyMeters: Double = 8
    private let degradedFixAgeSeconds: Double = 8
    @State private var editState: BuildingEditState?
    @State private var isPreparingEdit = false
    @State private var isSavingEdit = false
    @State private var editError: String?
    @State private var showEditScopeChoice = false
    
    @AppStorage("nav.avoidStairs")    private var prefAvoidStairs:    Bool = false
    @AppStorage("nav.elevatorsOnly")  private var prefElevatorsOnly:  Bool = false
    @AppStorage("nav.accessibleOnly") private var prefAccessibleOnly: Bool = false

    var body: some View {
        ZStack {
            Color.gray.opacity(0.05).ignoresSafeArea()

            MapViewWithOverlay(
                coordinate: userLocation ?? CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683),
                showFloorOverlay: $showFloorOverlay,
                rooms: floorService.rooms,
                buildings: knownBuildings,
                routeCoordinates: routeCoordinates,
                walkedCoordinates: walkedCoordinates,
                forcedLocation: liveDotLocation,
                showsUserLocation: liveDotLocation == nil,
                actionProxy: mapProxy,
                lastBuildingId: lastBuildingId,
                lastBuildingCoordinate: lastBuildingCoordinate,
                editState: $editState,
                onBuildingZoom: { buildingId, buildingCoord in
                    let changedBuilding = (buildingId != self.currentBuildingId)
                    self.currentBuildingCoordinate = buildingCoord
                    if changedBuilding {
                        self.currentBuildingId = buildingId
                        self.showFloorOverlay = true
                        self.diContainer.currentBuildingId = buildingId
                        self.diContainer.currentCampusId =
                            floorService.buildings.first { $0.id == buildingId }?.campusId
                        loadFloorsAndOverlay(buildingId: buildingId)
                        refreshCurrentBuildingOrgId()
                    } else if mapNav.pendingDestinationSpaceId != nil {
                        loadBuildingFloorData(buildingId: buildingId)
                    }
                },
                onZoomOut: {
                    if let cur = self.currentBuildingId {
                        self.lastBuildingId = cur
                        self.lastBuildingCoordinate = self.currentBuildingCoordinate
                    }
                    self.showFloorOverlay  = false
                    self.currentBuildingId = nil
                    self.currentBuildingOrgId = nil
                    self.currentBuildingCoordinate = nil
                    self.diContainer.currentBuildingId = nil
                    self.diContainer.currentCampusId = nil
                    self.diContainer.currentFloorIndex = nil
                    barometer.stop()
                },
                onRoomTap: { room in
                    let center: CLLocationCoordinate2D? = room.centroidGlobal ?? {
                        guard let p = room.polygonGlobal, !p.isEmpty else { return nil }
                        let lat = p.reduce(0.0) { $0 + $1.latitude } / Double(p.count)
                        let lng = p.reduce(0.0) { $0 + $1.longitude } / Double(p.count)
                        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    }()
                    pendingRouteSuggestion = SpaceSuggestion(
                        id: room.id,
                        name: room.name,
                        buildingId: currentBuildingId,
                        floorId: activeFloorId(in: floorService.floors),
                        campusId: nil,
                        lat: center?.latitude,
                        lon: center?.longitude
                    )
                    routeDestination = RouteDestination(
                        title: room.name,
                        subtitle: "Tap the arrow to get directions",
                        steps: []
                    )
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
                if showSnapConfirmation {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Landmark recognised, user location updated!")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.45)))
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let msg = arrivalBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                            .foregroundStyle(.green)
                        Text(msg)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.5)))
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                forcedLocationBanner
                SearchBar(text: $searchText, onSearch: handleSearch)
                    .padding(.horizontal, 16)

                if !floorService.suggestions.isEmpty && !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(floorService.suggestions, id: \.id) { s in
                                Button(action: {
                                    searchText = ""
                                    floorService.suggestions = []
                                    UIApplication.shared.sendAction(
                                        #selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil
                                    )
                                    pendingRouteSuggestion = s
                                    routeDestination = RouteDestination(
                                        title: s.name,
                                        subtitle: "Tap the arrow to get directions",
                                        steps: []
                                    )
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(s.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.black)
                                            HStack {
                                                if let bid = s.buildingId { Text(bid).font(.system(size: 12)).foregroundColor(.gray) }
                                                Spacer()
                                                if let campus = s.campusId { Text(campus).font(.system(size: 12)).foregroundColor(.gray) }
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 8)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
                }

                HStack(alignment: .center) {
                    LocationTypePill(
                        label: locationTypeLabel,
                        icon:  locationTypeIcon
                    )

                    Spacer()

                    if showFloorOverlay {
                        RefreshButton(isRefreshing: floorService.isLoading) {
                            if let buildingId = currentBuildingId {
                                loadBuildingFloorData(buildingId: buildingId)
                            }
                        }
                    }

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
            if let edit = editState {
                BuildingEditPanel(
                    state: edit,
                    isSaving: isSavingEdit,
                    errorText: editError,
                    onReset: {
                        editState?.deltaLat = 0
                        editState?.deltaLng = 0
                        editState?.deltaBearing = 0
                        editState?.scaleMultiplier = 1
                    },
                    onCancel: { editState = nil; editError = nil },
                    onSave: { Task { await saveEdit() } }
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        if showFloorOverlay && canEditBuildings {
                            Button {
                                showEditScopeChoice = true
                            } label: {
                                HStack(spacing: 6) {
                                    if isPreparingEdit {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                    Text("Edit")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .foregroundStyle(.white)
                                .background(Color.orange, in: Capsule())
                                .shadow(color: Color.orange.opacity(0.35), radius: 10, x: 0, y: 6)
                            }
                            .disabled(isPreparingEdit)
                            .padding(.leading, 16)
                        }

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

                    if let editError {
                        Text(editError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.red, in: Capsule())
                    }

                    if let dest = routeDestination {
                        let progress: NavigationProgress? = nextStep().map {
                            NavigationProgress(
                                instruction: $0.step.instruction,
                                distanceMeters: $0.distance,
                                remainingSteps: $0.remaining
                            )
                        }
                        BottomRouteCard(
                            destination: dest,
                            navigation: progress,
                            hasRoute: navigationService.currentRoute != nil,
                            isNavigating: isNavigating,
                            onDismiss: cancelRoute,
                            onNavigate: {
                                resolveRoute(to: dest.title, suggestion: pendingRouteSuggestion)
                            },
                            onStart: startNavigation,
                            onStop: stopNavigation
                        )
                        .padding(.horizontal, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }

        .navigationTitle("Floor Plan")
        .confirmationDialog("What do you want to edit?", isPresented: $showEditScopeChoice, titleVisibility: .visible) {
            Button("Edit Building") { Task { await beginEdit(scope: .building) } }
            Button("Edit This Floor") { Task { await beginEdit(scope: .floor) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Edit Building repositions every floor together. Edit This Floor moves only the floor you're viewing.")
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
        .onChange(of: searchText) { newValue in
            searchTask?.cancel()
            let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 1 else {
                floorService.suggestions = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await floorService.searchGlobal(q)
            }
        }
        .onChange(of: vm.selectedFloor) { _ in
            if showFloorOverlay, let buildingId = currentBuildingId {
                loadBuildingFloorData(buildingId: buildingId)
            }
            diContainer.currentFloorIndex = displayedFloorIndex
            rebuildRouteCoordinates(navigationService.currentRoute)
        }
        .onChange(of: mapNav.pendingBuildingId) { _ in consumePendingBuildingTarget() }
        .onChange(of: floorService.buildings.count) { _ in consumePendingBuildingTarget() }
        .onChange(of: mapNav.selectedTab) { newTab in
            guard newTab == .floorPlan,
                  showFloorOverlay,
                  let buildingId = currentBuildingId,
                  mapNav.pendingFloorId == nil,
                  mapNav.pendingFloorIndex == nil,
                  diContainer.forcedUserSpaceId == nil
            else { return }
            loadBuildingFloorData(buildingId: buildingId)
        }
        .onChange(of: navigationService.currentRoute) { route in
            rebuildRouteCoordinates(route)
            if isNavigating { initSimulationProgress() }
        }
        .onReceive(locationManager.$lastLocation) { _ in
            rebuildRouteCoordinates(navigationService.currentRoute)
            checkArrival()
            checkOffRoute()
        }
        .onReceive(locationManager.$lastLocation) { _ in syncFromLocationManager() }
        .onReceive(locationManager.$horizontalAccuracyMeters) { _ in syncFromLocationManager() }
        .onChange(of: diContainer.forcedUserSpaceId) { newValue in
            lastAnchoredForcedSpaceId = nil
            forcedSpaceHasAnchored = false   // new snap → allow floor auto-switch once
            if let spaceId = newValue {
                forcedSpaceFloorId    = mapNav.pendingFloorId
                forcedSpaceFloorIndex = mapNav.pendingFloorIndex

                let floors = floorService.floors
                if !floors.isEmpty {
                    var matchedIdx: Int?
                    if let pid = forcedSpaceFloorId,
                       let i = floors.firstIndex(where: { $0.id == pid }) {
                        matchedIdx = i
                    } else if let target = forcedSpaceFloorIndex,
                              let i = floors.firstIndex(where: { $0.floorIndex == target }) {
                        matchedIdx = i
                    }
                    if let idx = matchedIdx {
                        if vm.selectedFloor != idx { vm.selectedFloor = idx }
                        barometer.recalibrate(toFloorIndex: floors[idx].floorIndex)
                    }
                }

                if forcedSpaceFloorId == nil && forcedSpaceFloorIndex == nil {
                    Task {
                        guard let floorIdx = await floorService.fetchSpaceFloorIndex(spaceId: spaceId) else { return }
                        await MainActor.run {
                            guard diContainer.forcedUserSpaceId == spaceId else { return }
                            forcedSpaceFloorIndex = floorIdx
                            let currentFloors = floorService.floors
                            if let i = currentFloors.firstIndex(where: { $0.floorIndex == floorIdx }) {
                                if vm.selectedFloor != i {
                                    vm.selectedFloor = i
                                    barometer.recalibrate(toFloorIndex: floorIdx)
                                }
                            }
                            if mapNav.pendingFloorIndex == nil {
                                mapNav.pendingFloorIndex = floorIdx
                            }
                            applyForcedLocationIfReady()
                        }
                    }
                }
            } else {
                forcedSpaceFloorId    = nil
                forcedSpaceFloorIndex = nil
            }

            applyForcedLocationIfReady()
            if newValue != nil { flashSnapConfirmation() }
        }
        .onChange(of: floorService.rooms.map(\.id)) { _ in applyForcedLocationIfReady() }
        .onChange(of: floorService.floors.map(\.id)) { _ in applyForcedLocationIfReady() }
        .onChange(of: barometer.currentFloorIndex) { newFloor in
            guard diContainer.forcedUserSpaceId == nil else { return }
            guard let newFloor,
                  let labels = vm.availableFloorLabels,
                  let summaries = floorService.floors as [FloorSummary]?,
                  let idx = summaries.firstIndex(where: { $0.floorIndex == newFloor }),
                  vm.selectedFloor != idx,
                  idx < labels.count else { return }
            print("[FLOORPLAN] auto-switch to floor \(newFloor) from barometer")
            vm.selectedFloor = idx
        }
    }

    private func nextStep() -> (step: NavigationStep, distance: CLLocationDistance, remaining: Int)? {
        guard let route = navigationService.currentRoute, !route.steps.isEmpty,
              let user = userLocation else { return nil }
        let arrivalRadius: CLLocationDistance = 5
        let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)

        var upcoming: NavigationStep?
        var upcomingDistance: CLLocationDistance = .greatestFiniteMagnitude
        var remaining = 0

        for step in route.steps {
            guard let coord = step.coordinate else { continue }
            let d = userLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if d > arrivalRadius {
                if upcoming == nil {
                    upcoming = step
                    upcomingDistance = d
                }
                remaining += 1
            }
        }
        guard let upcoming else { return nil }
        return (upcoming, upcomingDistance, remaining)
    }

    private func cancelRoute() {
        navigationService.currentRoute = nil
        routeCoordinates = []
        walkedCoordinates = []
        routeDestination = nil
        pendingRouteSuggestion = nil
        searchText = ""
        if isNavigating {
            mapProxy.stopFollowingUser()
        }
        isNavigating = false
        isResolvingRoute = false
        teardownSimulation()
    }

    private func startNavigation() {
        guard navigationService.currentRoute != nil else { return }
        isNavigating = true
        arrivalBanner = nil
        mapProxy.startFollowingUser()
        // Dead-reckoning advances at constant average walking speed — no
        // hardware motion sensor needed. motionDetector is not started.
        initSimulationProgress()
        startSimulationTimer()
    }

    private func stopNavigation() {
        isNavigating = false
        mapProxy.stopFollowingUser()
        teardownSimulation()
    }

    private func startSimulationTimer() {
        simulationTimer?.invalidate()
        lastSimulationTick = Date()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async { self.tickSimulation() }
        }
        simulationTimer = t
    }

    private func teardownSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        simulatedPosition = nil
        simulatedArcLengthMeters = 0
        lastSimulationTick = nil
        lastAnchoredForcedSpaceId = nil
    }

    private func tickSimulation() {
        guard isNavigating else { teardownSimulation(); return }
        guard routeCoordinates.count >= 2 else {
            simulatedPosition = nil
            return
        }
        let now = Date()
        let dt = lastSimulationTick.map { now.timeIntervalSince($0) } ?? 0.5
        lastSimulationTick = now

        let forcedId = diContainer.forcedUserSpaceId
        if let forcedId, forcedId != lastAnchoredForcedSpaceId,
           let snapped = forcedLocationOnCurrentFloor {
            simulatedPosition = snapped
            rebuildRouteCoordinates(navigationService.currentRoute)
            simulatedArcLengthMeters = 0   // dead-reckoning will advance from snapped
            lastAnchoredForcedSpaceId = forcedId
            return   // anchor tick — next tick advances via phase 3
        }

        let fix = locationManager.lastLocation
        let fresh = fix.map { now.timeIntervalSince($0.timestamp) <= degradedFixAgeSeconds } ?? false
        let accurate = (locationManager.horizontalAccuracyMeters ?? .greatestFiniteMagnitude)
            <= degradedAccuracyMeters
        let blueDotReliable = fresh && accurate

        if blueDotReliable {
            simulatedPosition = nil
            simulatedArcLengthMeters = 0
            return
        }

        simulatedArcLengthMeters += dt * averageWalkingSpeedMS
        guard let newSim = coordinate(
            atArcLength: simulatedArcLengthMeters,
            on: routeCoordinates
        ) else { return }

        simulatedPosition = newSim
        simulatedArcLengthMeters = 0
        rebuildRouteCoordinates(navigationService.currentRoute)

        if let route = navigationService.currentRoute,
           let finalStep = route.steps.last,
           let dest = finalStep.coordinate,
           finalStep.floorIndex == displayedFloorIndex,
           haversineMeters(newSim, dest) <= arrivalRadiusMeters {
            announceArrival()
        }
    }

    private func announceArrival() {
        withAnimation { arrivalBanner = "You have reached your destination." }
        cancelRoute()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { arrivalBanner = nil }
        }
    }

    private func initSimulationProgress() {
        guard routeCoordinates.count >= 2 else {
            simulatedArcLengthMeters = 0
            simulatedPosition = nil
            return
        }
        if let user = userLocation {
            let (_, arc) = projectAndArcLength(user, route: routeCoordinates)
            simulatedArcLengthMeters = arc
        } else {
            simulatedArcLengthMeters = 0
        }
        simulatedPosition = nil
    }

    private func projectAndArcLength(
        _ p: CLLocationCoordinate2D,
        route: [CLLocationCoordinate2D]
    ) -> (CLLocationCoordinate2D, Double) {
        if route.count < 2 { return (p, 0) }
        var bestArc = 0.0
        var bestProj = route[0]
        var bestDist = Double.greatestFiniteMagnitude
        var acc = 0.0
        for i in 0..<(route.count - 1) {
            let segLen = haversineMeters(route[i], route[i + 1])
            let (proj, dist) = projectOntoSegment(p, route[i], route[i + 1])
            if dist < bestDist {
                bestDist = dist
                bestProj = proj
                bestArc = acc + haversineMeters(route[i], proj)
            }
            acc += segLen
        }
        return (bestProj, bestArc)
    }

    private func coordinate(
        atArcLength target: Double,
        on route: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        if route.isEmpty { return nil }
        if target <= 0 { return route.first }
        var acc = 0.0
        for i in 0..<(route.count - 1) {
            let segLen = haversineMeters(route[i], route[i + 1])
            if acc + segLen >= target {
                let t = (target - acc) / max(segLen, 0.0001)
                let lat = route[i].latitude + t * (route[i + 1].latitude - route[i].latitude)
                let lng = route[i].longitude + t * (route[i + 1].longitude - route[i].longitude)
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
            acc += segLen
        }
        return route.last
    }

    private func haversineMeters(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180
        let dlat = (b.latitude - a.latitude) * .pi / 180
        let dlng = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dlat / 2) * sin(dlat / 2)
              + cos(la1) * cos(la2) * sin(dlng / 2) * sin(dlng / 2)
        return 2 * 6_371_000 * atan2(sqrt(h), sqrt(1 - h))
    }

    private func checkArrival() {
        guard let route = navigationService.currentRoute,
              let user = userLocation else { return }
        let arrivalRadius: CLLocationDistance = 5

        let endCoord: CLLocationCoordinate2D?
        if let last = route.polyline.last, last.count >= 2 {
            endCoord = CLLocationCoordinate2D(latitude: last[0], longitude: last[1])
        } else {
            endCoord = route.steps.reversed().lazy
                .compactMap { $0.coordinate }
                .first
        }
        guard let end = endCoord else { return }
        let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
        if userLoc.distance(from: endLoc) <= arrivalRadius {
            announceArrival()
        }
    }

    private var liveDotLocation: CLLocationCoordinate2D? {
        if let sim = simulatedPosition, userOnRouteFloor { return sim }
        return forcedLocationOnCurrentFloor
    }

    private var forcedLocationOnCurrentFloor: CLLocationCoordinate2D? {
        guard let sid = diContainer.forcedUserSpaceId else { return nil }
        guard let room = floorService.rooms.first(where: { $0.id == sid }) else {
            return nil
        }
        if let exact = diContainer.forcedUserCoordinate { return exact }
        if let c = room.centroidGlobal { return c }
        if let p = room.polygonGlobal, !p.isEmpty {
            let lat = p.reduce(0.0) { $0 + $1.latitude } / Double(p.count)
            let lng = p.reduce(0.0) { $0 + $1.longitude } / Double(p.count)
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return nil
    }

    private var displayedFloorIndex: Int? {
        let i = vm.selectedFloor
        guard floorService.floors.indices.contains(i) else { return nil }
        return floorService.floors[i].floorIndex
    }

    private func rebuildRouteCoordinates(_ route: NavigationRoute?) {
        guard let r = route else { routeCoordinates = []; walkedCoordinates = []; return }

        let routeFloors = Set(r.steps.compactMap { $0.floorIndex })
        let isMultiFloor = routeFloors.count > 1

        let target = displayedFloorIndex
        let pathCoords: [CLLocationCoordinate2D]

        let toPoly: ([[Double]]) -> [CLLocationCoordinate2D] = { raw in
            raw.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            }
        }

        if !isMultiFloor, !r.polyline.isEmpty {
            pathCoords = toPoly(r.polyline)
        } else if let target, let floorPoly = r.polylinesByFloor[target], !floorPoly.isEmpty {
            pathCoords = toPoly(floorPoly)
        } else if let target {
            pathCoords = sliceStepsForFloor(r.steps, displayedFloor: target)
        } else {
            pathCoords = r.steps.compactMap { $0.coordinate }
        }

        let forcedSpaceOnDisplayedFloor: Bool = {
            guard let sid = diContainer.forcedUserSpaceId else { return false }
            return floorService.rooms.contains { $0.id == sid }
        }()
        let userOnThisFloor: Bool
        if forcedSpaceOnDisplayedFloor {
            userOnThisFloor = true
        } else if let target, let physical = barometer.currentFloorIndex {
            userOnThisFloor = (physical == target)
        } else {
            userOnThisFloor = !isMultiFloor
        }

        let routeStartFloor = r.steps.first(where: { $0.floorIndex != nil })?.floorIndex
        let displayedIsRouteStart: Bool = {
            guard isMultiFloor else { return true }
            guard let target, let start = routeStartFloor else { return false }
            return target == start
        }()

        userOnRouteFloor = userOnThisFloor
        let anchor: CLLocationCoordinate2D? = liveDotLocation ?? userLocation
        if let anchor, userOnThisFloor, displayedIsRouteStart {
            let (walked, remaining) = splitRoute(pathCoords, anchor: anchor)
            walkedCoordinates = walked
            routeCoordinates = [anchor] + remaining
        } else {
            walkedCoordinates = []
            routeCoordinates = pathCoords
        }
    }
    private func checkOffRoute() {
        guard navigationService.currentRoute != nil,
              !isRerouting,
              userOnRouteFloor,
              let user = userLocation,
              let dest = pendingRouteSuggestion,
              routeCoordinates.count >= 2 else { return }

        let deviation = routeDeviationMeters(routeCoordinates, anchor: user)
        if deviation > 15 {
            offRouteStreak += 1
            if offRouteStreak >= 2 {
                offRouteStreak = 0
                reroute(to: dest, from: user)
            }
        } else {
            offRouteStreak = 0
        }
    }

    private func reroute(to dest: SpaceSuggestion, from user: CLLocationCoordinate2D) {
        isRerouting = true
        Task {
            await navigationService.computeRoute(
                fromLatitude: user.latitude,
                longitude: user.longitude,
                to: dest.id,
                avoidStairs: prefAvoidStairs,
                elevatorsOnly: prefElevatorsOnly,
                accessibleOnly: prefAccessibleOnly
            )
            await MainActor.run { isRerouting = false }
        }
    }

    private func routeDeviationMeters(
        _ route: [CLLocationCoordinate2D],
        anchor: CLLocationCoordinate2D
    ) -> Double {
        guard route.count >= 2 else { return 0 }
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(route.count - 1) {
            let (_, d) = projectOntoSegment(anchor, route[i], route[i + 1])
            if d < best { best = d }
        }
        return best
    }

    private func splitRoute(
        _ route: [CLLocationCoordinate2D],
        anchor: CLLocationCoordinate2D
    ) -> (walked: [CLLocationCoordinate2D], remaining: [CLLocationCoordinate2D]) {
        guard route.count >= 2 else { return ([], route) }

        var bestSeg = 0
        var bestProj = route[0]
        var bestDist = Double.greatestFiniteMagnitude
        for i in 0..<(route.count - 1) {
            let (proj, dist) = projectOntoSegment(anchor, route[i], route[i + 1])
            if dist < bestDist {
                bestDist = dist
                bestSeg = i
                bestProj = proj
            }
        }

        let walked = Array(route[0...bestSeg]) + [bestProj]
        let remaining = [bestProj] + Array(route[(bestSeg + 1)...])
        return (walked, remaining)
    }

    private func projectOntoSegment(
        _ p: CLLocationCoordinate2D,
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> (CLLocationCoordinate2D, Double) {
        let mPerDegLat = 111_320.0
        let mPerDegLng = 111_320.0 * cos(a.latitude * .pi / 180)
        let ax = a.longitude * mPerDegLng, ay = a.latitude * mPerDegLat
        let bx = b.longitude * mPerDegLng, by = b.latitude * mPerDegLat
        let px = p.longitude * mPerDegLng, py = p.latitude * mPerDegLat
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
        let projLat = a.latitude + t * (b.latitude - a.latitude)
        let projLng = a.longitude + t * (b.longitude - a.longitude)
        let ex = px - (ax + t * dx), ey = py - (ay + t * dy)
        return (
            CLLocationCoordinate2D(latitude: projLat, longitude: projLng),
            (ex * ex + ey * ey).squareRoot()
        )
    }

    private func sliceStepsForFloor(
        _ steps: [NavigationStep],
        displayedFloor: Int
    ) -> [CLLocationCoordinate2D] {
        return steps.compactMap { step in
            guard step.floorIndex == displayedFloor,
                  let coord = step.coordinate else { return nil }
            return coord
        }
    }

    private var knownBuildings: [BuildingLocator] {
        var merged = floorService.buildings
        let knownIds = Set(merged.map { $0.id })
        for b in visitedBuildings where !knownIds.contains(b.id) {
            merged.append(b)
        }
        return merged
    }

    private func rememberVisited(id: String, name: String?, coordinate: CLLocationCoordinate2D) {
        if visitedBuildings.contains(where: { $0.id == id }) { return }
        visitedBuildings.append(BuildingLocator(id: id, name: name ?? id, coordinate: coordinate))
    }

    private func consumePendingBuildingTarget() {
        guard let pending = mapNav.pendingBuildingId else { return }
        let pendingName = mapNav.pendingBuildingName
        if let building = floorService.buildings.first(where: { $0.id == pending }) {
            print("[NAV] flying to building \(building.name) at \(building.coordinate) and loading floors directly")
            mapProxy.flyTo(building.coordinate)
            currentBuildingId = pending
            currentBuildingCoordinate = building.coordinate
            rememberVisited(id: pending, name: building.name, coordinate: building.coordinate)
            floorService.rooms = []
            showFloorOverlay = true
            loadFloorsAndOverlay(buildingId: pending)
            refreshCurrentBuildingOrgId()
            mapNav.pendingBuildingCoordinate = nil
            mapNav.pendingBuildingId = nil
            mapNav.pendingBuildingName = nil
            return
        }

        if let coord = mapNav.pendingBuildingCoordinate {
            print("[NAV] fallback fly-to coordinate for building \(pending) -> \(coord)")
            mapProxy.flyTo(coord)
            currentBuildingId = pending
            currentBuildingCoordinate = coord
            rememberVisited(id: pending, name: pendingName, coordinate: coord)
            floorService.rooms = []
            showFloorOverlay = true
            loadFloorsAndOverlay(buildingId: pending)
            refreshCurrentBuildingOrgId()
            mapNav.pendingBuildingCoordinate = nil
            mapNav.pendingBuildingId = nil
            mapNav.pendingBuildingName = nil
            return
        }

        print("[NAV] no coord for building \(pending), loading floors without flying")
        currentBuildingId = pending
        floorService.rooms = []
        showFloorOverlay = true
        loadFloorsAndOverlay(buildingId: pending)
        refreshCurrentBuildingOrgId()
        mapNav.pendingBuildingCoordinate = nil
        mapNav.pendingBuildingId = nil
        mapNav.pendingBuildingName = nil
    }

    private var canEditBuildings: Bool {
        guard let role = authService.principal?.role,
              role == "editor" || role == "owner" else { return false }
        guard let activeOrg = authService.principal?.organizationId,
              let buildingOrg = currentBuildingOrgId else { return false }
        return activeOrg == buildingOrg
    }

    private func refreshCurrentBuildingOrgId() {
        guard let id = currentBuildingId else {
            currentBuildingOrgId = nil
            return
        }
        currentBuildingOrgId = nil
        Task {
            let detail = await floorService.fetchBuildingDetail(buildingId: id)
            await MainActor.run {
                if currentBuildingId == id {
                    currentBuildingOrgId = detail?.organizationId
                }
            }
        }
    }

    private func beginEdit(scope: BuildingEditScope) async {
        guard let buildingId = currentBuildingId else { return }
        editError = nil
        isPreparingEdit = true
        defer { isPreparingEdit = false }

        guard let detail = await floorService.fetchBuildingDetail(buildingId: buildingId) else {
            editError = "Couldn't load building details for editing."
            return
        }
        if let buildingOrg = detail.organizationId,
           let myOrg = authService.principal?.organizationId,
           buildingOrg != myOrg {
            editError = "You can only edit buildings in your own organization."
            return
        }

        switch scope {
        case .building:
            editState = BuildingEditState(
                scope: .building,
                buildingId: buildingId,
                floorId: nil,
                originLat: detail.originLat,
                originLng: detail.originLng,
                baseBearing: detail.originBearing,
                baseScale: detail.scaleFactor
            )
        case .floor:
            guard let floorId = activeFloorId(in: floorService.floors) else {
                editError = "No floor selected to edit."
                return
            }
            guard let floor = await floorService.fetchFloorDetail(floorId: floorId) else {
                editError = "Couldn't load floor details for editing."
                return
            }
            editState = BuildingEditState(
                scope: .floor,
                buildingId: buildingId,
                floorId: floorId,
                originLat: floor.originLat,
                originLng: floor.originLng,
                baseBearing: floor.originBearing,
                baseScale: floor.scaleFactor
            )
        }
    }

    private func saveEdit() async {
        guard let edit = editState else { return }
        editError = nil
        isSavingEdit = true
        defer { isSavingEdit = false }
        do {
            switch edit.scope {
            case .building:
                try await floorService.updateBuilding(
                    buildingId: edit.buildingId,
                    originLat: edit.newOriginLat,
                    originLng: edit.newOriginLng,
                    originBearing: edit.newBearing,
                    scaleFactor: edit.newScale
                )
            case .floor:
                guard let floorId = edit.floorId else { return }
                try await floorService.updateFloor(
                    floorId: floorId,
                    originLat: edit.newOriginLat,
                    originLng: edit.newOriginLng,
                    originBearing: edit.newBearing,
                    scaleFactor: edit.newScale
                )
            }
            editState = nil
            if let floorId = activeFloorId(in: floorService.floors) {
                await floorService.fetchFloorGeometry(floorId: floorId)
            }
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resolveRoute(to destination: String, suggestion: SpaceSuggestion? = nil) {
        routeDestination = RouteDestination(title: destination, subtitle: "Calculating route…", steps: [])
        isResolvingRoute = true

        var context: [String: Any] = [:]
        if let loc = userLocation {
            context["x"] = loc.longitude
            context["y"] = loc.latitude
        }
        if let bid = currentBuildingId {
            context["building_id"] = bid
            if let cid = floorService.buildings.first(where: { $0.id == bid })?.campusId
                ?? diContainer.currentCampusId {
                context["campus_id"] = cid
            }
        } else if let cid = diContainer.currentCampusId {
            context["campus_id"] = cid
        }

        let knownNow = knownBuildings
        let userLoc0 = userLocation
        let forcedSpaceId = diContainer.forcedUserSpaceId
        let currentBldId = currentBuildingId

        Task {

            let top: SpaceSuggestion?

            if let suggestion {
                top = suggestion
            } else {
                await floorService.searchGlobal(destination)
                top = floorService.suggestions.first
            }

            if forcedSpaceId == nil, let top, let loc = userLoc0 {
                let alreadyInsideBuilding = currentBldId != nil && currentBldId == top.buildingId
                if !alreadyInsideBuilding {
                    let building = top.buildingId.flatMap { id in
                        knownNow.first(where: { $0.id == id })
                    }
                    let target = building?.coordinate ?? top.coordinate
                    if let target {
                        let dist = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
                            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
                        if dist > 80 {
                            let buildingName = building?.name ?? "the building it's in"
                            await MainActor.run {
                                routeDestination = RouteDestination(
                                    title: destination,
                                    subtitle: "You're too far for indoor directions",
                                    steps: [
                                        "\(top.name) is in \(buildingName), about \(Int(dist)) m away.",
                                        "Indoor directions are only available once you're at or inside the building.",
                                        "Use the world map to walk there first, then ask again."
                                    ]
                                )
                                isResolvingRoute = false
                            }
                            return
                        }
                    }
                }
            }

            if let top, let fromId = forcedSpaceId {
                await navigationService.computeRoute(
                    from: fromId,
                    to: top.id,
                    avoidStairs: prefAvoidStairs,
                    elevatorsOnly: prefElevatorsOnly,
                    accessibleOnly: prefAccessibleOnly
                )
                if let route = navigationService.currentRoute {
                    let steps = route.steps.map { $0.instruction }
                    await MainActor.run {
                        routeDestination = RouteDestination(title: destination, subtitle: "Route ready", steps: steps)
                        isResolvingRoute = false
                    }
                    return
                }
            }

            if let top, let loc = userLoc0 {
                await navigationService.computeRoute(
                    fromLatitude: loc.latitude,
                    longitude: loc.longitude,
                    to: top.id,
                    avoidStairs: prefAvoidStairs,
                    elevatorsOnly: prefElevatorsOnly,
                    accessibleOnly: prefAccessibleOnly
                )
                if let route = navigationService.currentRoute {
                    let steps = route.steps.map { $0.instruction }
                    await MainActor.run {
                        routeDestination = RouteDestination(title: destination, subtitle: "Route ready", steps: steps)
                        isResolvingRoute = false
                    }
                    return
                }
            }

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
                let pendingId = mapNav.pendingFloorId
                let pendingBaseline = mapNav.pendingFloorIndex
                if !summaries.isEmpty {
                    if let pid = pendingId,
                       let i = summaries.firstIndex(where: { $0.id == pid }) {
                        vm.selectedFloor = i
                        mapNav.pendingFloorId = nil
                        mapNav.pendingFloorIndex = nil
                    } else if let target = pendingBaseline,
                       let i = summaries.firstIndex(where: { $0.floorIndex == target }) {
                        vm.selectedFloor = i
                        mapNav.pendingFloorIndex = nil
                        mapNav.pendingFloorId = nil
                    } else {
                        vm.selectedFloor = summaries.firstIndex { $0.floorIndex == 0 } ?? 0
                    }
                }
                let baseline = pendingBaseline
                    ?? summaries.first(where: { $0.id == pendingId })?.floorIndex
                    ?? 0
                barometer.start(
                    floors: summaries,
                    baselineFloorIndex: baseline
                )
            }
            if let active = activeFloorId(in: summaries) {
                await floorService.fetchFloorGeometry(floorId: active)
                await MainActor.run { consumePendingDestination() }
            }
        }
    }

    private func loadBuildingFloorData(buildingId: String) {
        guard let floorId = activeFloorId(in: floorService.floors) else { return }
        Task {
            await floorService.fetchFloorGeometry(floorId: floorId)
            await MainActor.run { consumePendingDestination() }
        }
    }

    private func consumePendingDestination() {
        guard let spaceId = mapNav.pendingDestinationSpaceId else { return }
        let room = floorService.rooms.first(where: { $0.id == spaceId })
        let name = mapNav.pendingDestinationSpaceName ?? room?.name ?? spaceId
        let coord: CLLocationCoordinate2D? = mapNav.pendingDestinationSpaceCoordinate
            ?? room?.centroidGlobal
            ?? {
                guard let p = room?.polygonGlobal, !p.isEmpty else { return nil }
                let lat = p.reduce(0.0) { $0 + $1.latitude } / Double(p.count)
                let lng = p.reduce(0.0) { $0 + $1.longitude } / Double(p.count)
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }()
        pendingRouteSuggestion = SpaceSuggestion(
            id: spaceId,
            name: name,
            buildingId: currentBuildingId,
            floorId: activeFloorId(in: floorService.floors),
            campusId: nil,
            lat: coord?.latitude,
            lon: coord?.longitude
        )
        routeDestination = RouteDestination(
            title: name,
            subtitle: "Tap the arrow to get directions",
            steps: []
        )
        mapNav.pendingDestinationSpaceId = nil
        mapNav.pendingDestinationSpaceName = nil
        mapNav.pendingDestinationSpaceCoordinate = nil
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
        if diContainer.forcedUserSpaceId == nil,
           let loc = locationManager.lastLocation {
            userLocation = loc.coordinate
        }
        locationAccuracy = locationManager.horizontalAccuracyMeters
        if let loc = locationManager.lastLocation {
            diContainer.lastKnownUserCoordinate = loc.coordinate
        }
    }

    private func flashSnapConfirmation() {
        withAnimation { showSnapConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showSnapConfirmation = false }
        }
    }

    private func applyForcedLocationIfReady() {
        guard let spaceId = diContainer.forcedUserSpaceId else { return }

        if floorService.rooms.first(where: { $0.id == spaceId }) == nil {
            guard !forcedSpaceHasAnchored else { return }
            let floors = floorService.floors
            guard !floors.isEmpty else { return }
            var switchedIdx: Int?
            if let fid = forcedSpaceFloorId,
               let i = floors.firstIndex(where: { $0.id == fid }) {
                switchedIdx = i
            } else if let fi = forcedSpaceFloorIndex,
                      let i = floors.firstIndex(where: { $0.floorIndex == fi }) {
                switchedIdx = i
            }
            if let idx = switchedIdx, vm.selectedFloor != idx {
                print("[FLOORPLAN] applyForcedLocation: switching to floor idx=\(idx) for snap")
                vm.selectedFloor = idx
                barometer.recalibrate(toFloorIndex: floors[idx].floorIndex)
            }
            return
        }

        guard let room = floorService.rooms.first(where: { $0.id == spaceId }) else { return }
        let resolvedCoord: CLLocationCoordinate2D?
        if let coord = room.centroidGlobal {
            userLocation = coord
            locationAccuracy = 0  // exact: we know the room, not "GPS-ish"
            resolvedCoord = coord
        } else if let polygon = room.polygonGlobal, !polygon.isEmpty {
            let lat = polygon.reduce(0.0) { $0 + $1.latitude } / Double(polygon.count)
            let lng = polygon.reduce(0.0) { $0 + $1.longitude } / Double(polygon.count)
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            userLocation = coord
            locationAccuracy = 0
            resolvedCoord = coord
        } else {
            resolvedCoord = nil
        }
        if let coord = resolvedCoord {
            mapProxy.flyTo(coord)
        }
        // Mark anchored so subsequent room-load events (triggered when the user
        // browses to another floor) do not switch the floor back.
        forcedSpaceHasAnchored = true
    }

    private func handleSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        resolveRoute(to: q)
    }


    @ViewBuilder
    private var forcedLocationBanner: some View {
        if let spaceId = diContainer.forcedUserSpaceId {
            let room = floorService.rooms.first(where: { $0.id == spaceId })
            HStack(spacing: 10) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pinned to: \(room?.name ?? "registered landmark")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Tap × to return to GPS")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 8)
                Button {
                    diContainer.forcedUserSpaceId = nil
                    diContainer.forcedUserCoordinate = nil
                    syncFromLocationManager()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.75),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.yellow.opacity(0.5))
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
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
            if floorService.floors.indices.contains(idx) {
                barometer.recalibrate(toFloorIndex: floorService.floors[idx].floorIndex)
            }
        }
    }
}

//Map View with Overlay

final class ForcedLocationAnnotation: MKPointAnnotation {}

struct MapViewWithOverlay: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    @Binding var showFloorOverlay: Bool
    let rooms: [Room]
    let buildings: [BuildingLocator]
    let routeCoordinates: [CLLocationCoordinate2D]
    // The portion of the route already walked (behind the user), drawn dimmed
    // so the active blue line shrinks toward the destination as the user moves.
    let walkedCoordinates: [CLLocationCoordinate2D]
    let forcedLocation: CLLocationCoordinate2D?
    let showsUserLocation: Bool
    let actionProxy: MapActionProxy
    let lastBuildingId: String?
    let lastBuildingCoordinate: CLLocationCoordinate2D?
    @Binding var editState: BuildingEditState?
    let onBuildingZoom: (String, CLLocationCoordinate2D) -> Void
    let onZoomOut: () -> Void
    let onRoomTap: (Room) -> Void

    private static let indoorZoomThreshold = 0.005
    private static let visibilityPaddingMeters: CLLocationDistance = 150

    static func applyEditTransform(
        _ coord: CLLocationCoordinate2D,
        _ e: BuildingEditState
    ) -> CLLocationCoordinate2D {
        let mPerDegLat = 111_000.0
        let mPerDegLng = 111_000.0 * cos(e.originLat * .pi / 180)
        let dxM = (coord.longitude - e.originLng) * mPerDegLng
        let dyM = (coord.latitude - e.originLat) * mPerDegLat
        let b = e.deltaBearing * .pi / 180
        let rx = dxM * cos(b) - dyM * sin(b)
        let ry = dxM * sin(b) + dyM * cos(b)
        let sx = rx * e.scaleMultiplier
        let sy = ry * e.scaleMultiplier
        let newLng = e.originLng + e.deltaLng + sx / mPerDegLng
        let newLat = e.originLat + e.deltaLat + sy / mPerDegLat
        return CLLocationCoordinate2D(latitude: newLat, longitude: newLng)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation   = showsUserLocation
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

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleEditPan(_:))
        )
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleEditPinch(_:))
        )
        let rotation = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleEditRotation(_:))
        )
        for gr in [pan, pinch, rotation] as [UIGestureRecognizer] {
            gr.delegate = context.coordinator
            gr.isEnabled = false
            mapView.addGestureRecognizer(gr)
        }
        context.coordinator.editPan = pan
        context.coordinator.editPinch = pinch
        context.coordinator.editRotation = rotation

        // Tap-to-select-room. cancelsTouchesInView=false so MapKit's own
        // gestures (annotation selection, scroll) keep working.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRoomTap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self
        if actionProxy.mapView == nil { actionProxy.mapView = uiView }
        // Toggle MapKit's own blue dot in sync with the custom dot. Without
        // this both would race during a landmark snap / simulation switch.
        if uiView.showsUserLocation != showsUserLocation {
            uiView.showsUserLocation = showsUserLocation
        }
        if !context.coordinator.initialRegionSet {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            uiView.setRegion(region, animated: false)
            context.coordinator.initialRegionSet = true
        }

        let editing = editState != nil
        context.coordinator.editPan?.isEnabled = editing
        context.coordinator.editPinch?.isEnabled = editing
        context.coordinator.editRotation?.isEnabled = editing
        uiView.isScrollEnabled = !editing
        uiView.isZoomEnabled = !editing
        uiView.isRotateEnabled = !editing
        uiView.isPitchEnabled = !editing

        // Rooms: persistent custom overlay.
        if context.coordinator.roomsOverlay == nil {
            let ov = FloorRoomsOverlay()
            context.coordinator.roomsOverlay = ov
            uiView.addOverlay(ov, level: .aboveLabels)
        }
        let visibleRooms = showFloorOverlay ? rooms : []
        let roomsSig = roomsSignature(visibleRooms)
        let editSig = editSignature(editState)
        if roomsSig != context.coordinator.cachedRoomsSig ||
           editSig != context.coordinator.cachedEditSig {
            context.coordinator.roomsRenderer?.rooms = visibleRooms
            context.coordinator.roomsRenderer?.editState = editState
            context.coordinator.roomsRenderer?.setNeedsDisplay()
            context.coordinator.cachedRoomsSig = roomsSig
            context.coordinator.cachedEditSig = editSig
        }

        let routeSig = polylineSignature(routeCoordinates)
        let walkedSig = polylineSignature(walkedCoordinates)
        if routeSig != context.coordinator.cachedRouteSig ||
           walkedSig != context.coordinator.cachedWalkedSig {
            let routeOverlays = uiView.overlays.filter { $0 is MKPolyline }
            uiView.removeOverlays(routeOverlays)

            if walkedCoordinates.count >= 2 {
                var walked = walkedCoordinates
                let trail = MKPolyline(coordinates: &walked, count: walked.count)
                trail.title = "route-walked"
                uiView.addOverlay(trail, level: .aboveLabels)
            }
            if routeCoordinates.count >= 2 {
                var coords = routeCoordinates
                let halo = MKPolyline(coordinates: &coords, count: coords.count)
                halo.title = "route-halo"
                let main = MKPolyline(coordinates: &coords, count: coords.count)
                main.title = "route-main"
                uiView.addOverlay(halo, level: .aboveLabels)
                uiView.addOverlay(main, level: .aboveLabels)
            }
            context.coordinator.cachedRouteSig = routeSig
            context.coordinator.cachedWalkedSig = walkedSig

            if let last = routeCoordinates.last, routeCoordinates.count >= 2 {
                if let existing = context.coordinator.destinationAnnotation {
                    existing.coordinate = last
                } else {
                    let pin = MKPointAnnotation()
                    pin.coordinate = last
                    pin.title = "Destination"
                    uiView.addAnnotation(pin)
                    context.coordinator.destinationAnnotation = pin
                }
            } else if let existing = context.coordinator.destinationAnnotation {
                uiView.removeAnnotation(existing)
                context.coordinator.destinationAnnotation = nil
            }
        }

        if let forced = forcedLocation {
            if let existing = context.coordinator.forcedAnnotation {
                if existing.coordinate.latitude != forced.latitude
                    || existing.coordinate.longitude != forced.longitude {
                    existing.coordinate = forced
                }
            } else {
                let dot = ForcedLocationAnnotation()
                dot.coordinate = forced
                dot.title = "You are here"
                uiView.addAnnotation(dot)
                context.coordinator.forcedAnnotation = dot
            }
            context.coordinator.cachedForcedLat = forced.latitude
            context.coordinator.cachedForcedLng = forced.longitude
        } else if let existing = context.coordinator.forcedAnnotation {
            uiView.removeAnnotation(existing)
            context.coordinator.forcedAnnotation = nil
            context.coordinator.cachedForcedLat = .nan
            context.coordinator.cachedForcedLng = .nan
        }
    }

    private func roomsSignature(_ rs: [Room]) -> Int {
        var hasher = Hasher()
        hasher.combine(rs.count)
        for r in rs { hasher.combine(r.id) }
        return hasher.finalize()
    }

    private func editSignature(_ e: BuildingEditState?) -> Int {
        guard let e = e else { return 0 }
        var hasher = Hasher()
        hasher.combine(e.deltaLat)
        hasher.combine(e.deltaLng)
        hasher.combine(e.deltaBearing)
        hasher.combine(e.scaleMultiplier)
        return hasher.finalize()
    }

    private func polylineSignature(_ coords: [CLLocationCoordinate2D]) -> Int {
        var hasher = Hasher()
        hasher.combine(coords.count)
        if let first = coords.first {
            hasher.combine(first.latitude); hasher.combine(first.longitude)
        }
        if let last = coords.last {
            hasher.combine(last.latitude); hasher.combine(last.longitude)
        }
        return hasher.finalize()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapViewWithOverlay
        var initialRegionSet = false

        var roomsOverlay: FloorRoomsOverlay?
        weak var roomsRenderer: FloorRoomsRenderer?

        var cachedRoomsSig: Int = 0
        var cachedEditSig: Int = 0
        var cachedRouteSig: Int = -1
        var cachedWalkedSig: Int = -1
        var cachedForcedLat: Double = .nan
        var cachedForcedLng: Double = .nan
        weak var forcedAnnotation: ForcedLocationAnnotation?
        weak var destinationAnnotation: MKPointAnnotation?

        weak var editPan: UIPanGestureRecognizer?
        weak var editPinch: UIPinchGestureRecognizer?
        weak var editRotation: UIRotationGestureRecognizer?
        private var panBaseDeltaLat = 0.0
        private var panBaseDeltaLng = 0.0
        private var pinchBaseScale = 1.0
        private var rotationBaseBearing = 0.0

        init(_ parent: MapViewWithOverlay) { self.parent = parent }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if parent.editState != nil { return }
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

            let visibleRect = mapView.visibleMapRect
            let padPoints   = MKMapPointsPerMeterAtLatitude(mapView.centerCoordinate.latitude)
                              * MapViewWithOverlay.visibilityPaddingMeters
            let paddedRect  = visibleRect.insetBy(dx: -padPoints, dy: -padPoints)

            let center = CLLocation(
                latitude: mapView.centerCoordinate.latitude,
                longitude: mapView.centerCoordinate.longitude
            )

            var onScreen: [(BuildingLocator, CLLocationDistance)] = []
            for building in parent.buildings {
                let point = MKMapPoint(building.coordinate)
                guard paddedRect.contains(point) else { continue }
                let d = center.distance(from: CLLocation(
                    latitude: building.coordinate.latitude,
                    longitude: building.coordinate.longitude
                ))
                onScreen.append((building, d))
            }

            if onScreen.isEmpty {
                if let last = parent.lastBuildingId,
                   let lastCoord = parent.lastBuildingCoordinate,
                   paddedRect.contains(MKMapPoint(lastCoord)) {
                    print("[PROX] zoom=\(zoomLevel) no locators in view, last building's coord in rect → restoring \(last)")
                    parent.onBuildingZoom(last, lastCoord)
                } else {
                    print("[PROX] zoom=\(zoomLevel) no locators in view; last building not in rect — not restoring")
                }
                return
            }

            let pick: BuildingLocator
            if let last = parent.lastBuildingId,
               let restore = onScreen.first(where: { $0.0.id == last }) {
                pick = restore.0
                print("[PROX] zoom=\(zoomLevel) → restoring \(pick.name) (last-shown, in view)")
            } else {
                let nearest = onScreen.min(by: { $0.1 < $1.1 })!
                pick = nearest.0
                print("[PROX] zoom=\(zoomLevel) → \(pick.name) at \(Int(nearest.1))m centre, in view")
            }
            parent.onBuildingZoom(pick.id, pick.coordinate)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is ForcedLocationAnnotation else { return nil }
            let id = "forcedLocation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true
            let size: CGFloat = 18
            view.frame = CGRect(x: 0, y: 0, width: size, height: size)
            view.backgroundColor = .clear
            view.layer.sublayers?.removeAll()
            let dot = CAShapeLayer()
            dot.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).cgPath
            dot.fillColor = UIColor.systemRed.cgColor
            dot.strokeColor = UIColor.white.cgColor
            dot.lineWidth = 2.5
            dot.shadowColor = UIColor.black.cgColor
            dot.shadowOpacity = 0.35
            dot.shadowRadius = 3
            dot.shadowOffset = CGSize(width: 0, height: 1)
            view.layer.addSublayer(dot)
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                if polyline.title == "route-walked" {
                    r.strokeColor = UIColor(
                        red: 0.55, green: 0.58, blue: 0.62, alpha: 0.7
                    )
                    r.lineWidth = 5.0
                    r.lineDashPattern = [2, 8]  
                } else if polyline.title == "route-halo" {
                    r.strokeColor = UIColor(
                        red: 0.05, green: 0.30, blue: 0.66, alpha: 1.0
                    )
                    r.lineWidth = 11.0
                } else {
                    r.strokeColor = UIColor(
                        red: 0.26, green: 0.55, blue: 0.99, alpha: 1.0
                    )
                    r.lineWidth = 7.0
                }
                r.lineJoin = .round
                r.lineCap = .round
                return r
            }
            if let roomsOverlay = overlay as? FloorRoomsOverlay {
                let r = FloorRoomsRenderer(overlay: roomsOverlay)
                r.rooms = parent.showFloorOverlay ? parent.rooms : []
                r.editState = parent.editState
                roomsRenderer = r
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {true}

        @objc func handleRoomTap(_ g: UITapGestureRecognizer) {
            guard parent.editState == nil,
                  parent.showFloorOverlay,
                  let mv = g.view as? MKMapView
            else { return }
            let tapCoord = mv.convert(g.location(in: mv), toCoordinateFrom: mv)
            let tapPoint = MKMapPoint(tapCoord)
            let tapCG = CGPoint(x: tapPoint.x, y: tapPoint.y)
            let sortedRooms = parent.rooms.sorted {
                mapPointPolygonArea($0.polygonGlobal ?? []) < mapPointPolygonArea($1.polygonGlobal ?? [])
            }
            for room in sortedRooms {
                guard let poly = room.polygonGlobal, poly.count >= 3 else { continue }
                let path = CGMutablePath()
                for (i, c) in poly.enumerated() {
                    let p = MKMapPoint(c)
                    let cg = CGPoint(x: p.x, y: p.y)
                    if i == 0 { path.move(to: cg) } else { path.addLine(to: cg) }
                }
                path.closeSubpath()
                if path.contains(tapCG) {
                    parent.onRoomTap(room)
                    return
                }
            }
        }

        private func mapPointPolygonArea(_ coords: [CLLocationCoordinate2D]) -> Double {
            guard coords.count >= 3 else { return 0 }
            var area = 0.0
            let pts = coords.map { MKMapPoint($0) }
            let n = pts.count
            for i in 0..<n {
                let j = (i + 1) % n
                area += pts[i].x * pts[j].y
                area -= pts[j].x * pts[i].y
            }
            return abs(area) * 0.5
        }

        @objc func handleEditPan(_ g: UIPanGestureRecognizer) {
            guard parent.editState != nil, let mv = g.view as? MKMapView else { return }
            switch g.state {
            case .began:
                panBaseDeltaLat = parent.editState?.deltaLat ?? 0
                panBaseDeltaLng = parent.editState?.deltaLng ?? 0
            case .changed:
                let t = g.translation(in: mv)
                let center = CGPoint(x: mv.bounds.midX, y: mv.bounds.midY)
                let c0 = mv.convert(center, toCoordinateFrom: mv)
                let c1 = mv.convert(
                    CGPoint(x: center.x + t.x, y: center.y + t.y),
                    toCoordinateFrom: mv
                )
                var e = parent.editState
                e?.deltaLat = panBaseDeltaLat + (c1.latitude - c0.latitude)
                e?.deltaLng = panBaseDeltaLng + (c1.longitude - c0.longitude)
                parent.editState = e
            default:
                break
            }
        }

        @objc func handleEditPinch(_ g: UIPinchGestureRecognizer) {
            guard parent.editState != nil else { return }
            switch g.state {
            case .began:
                pinchBaseScale = parent.editState?.scaleMultiplier ?? 1
            case .changed:
                let next = pinchBaseScale * Double(g.scale)
                parent.editState?.scaleMultiplier = min(max(next, 0.2), 5.0)
            default:
                break
            }
        }

        @objc func handleEditRotation(_ g: UIRotationGestureRecognizer) {
            guard parent.editState != nil else { return }
            switch g.state {
            case .began:
                rotationBaseBearing = parent.editState?.deltaBearing ?? 0
            case .changed:
                let deg = Double(g.rotation) * 180 / .pi
                parent.editState?.deltaBearing = rotationBaseBearing - deg
            default:
                break
            }
        }
    }
}


final class FloorRoomsOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world
}

final class FloorRoomsRenderer: MKOverlayRenderer {
    var rooms: [Room] = []
    var editState: BuildingEditState?

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        let strokeColor = UIColor(white: 0.25, alpha: 0.9).cgColor
        let lineWidth = 2.0 / zoomScale
        for room in rooms {
            guard let raw = room.polygonGlobal, raw.count >= 3 else { continue }
            let coords: [CLLocationCoordinate2D] = editState.map { e in
                raw.map { MapViewWithOverlay.applyEditTransform($0, e) }
            } ?? raw

            let path = CGMutablePath()
            for (i, c) in coords.enumerated() {
                let p = point(for: MKMapPoint(c))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()

            ctx.addPath(path)
            ctx.setFillColor(Self.color(for: room.type.rawValue).withAlphaComponent(0.85).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(lineWidth)
            ctx.strokePath()
        }
    }

    static func color(for type: String) -> UIColor {
        switch type {
        case "hallway":  return UIColor(red: 0.62, green: 0.82, blue: 0.95, alpha: 1)  // corridors
        case "restroom": return UIColor(red: 1.00, green: 0.45, blue: 0.70, alpha: 1)  // bathrooms — pink
        case "elevator", "stairs", "connector":
                         return UIColor(red: 1.00, green: 0.58, blue: 0.10, alpha: 1)  // vertical/connectors — orange
        default:         return UIColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)  // rooms
        }
    }
}


struct NavigationProgress {
    let instruction: String
    let distanceMeters: CLLocationDistance
    let remainingSteps: Int

    var distanceLabel: String {
        if distanceMeters < 10 { return "Now" }
        if distanceMeters < 1000 { return "In \(Int(distanceMeters)) m" }
        return String(format: "In %.1f km", distanceMeters / 1000)
    }
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

private struct RefreshButton: View {
    let isRefreshing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .default,
                    value: isRefreshing
                )
        }
        .disabled(isRefreshing)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .padding(.trailing, 8)
    }
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

private struct BuildingEditPanel: View {
    let state: BuildingEditState
    let isSaving: Bool
    let errorText: String?
    let onReset: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    private var offsetMeters: Int {
        let dyM = state.deltaLat * 111_000
        let dxM = state.deltaLng * 111_000 * cos(state.originLat * .pi / 180)
        return Int((dxM * dxM + dyM * dyM).squareRoot().rounded())
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(state.scope == .building ? "Edit building" : "Edit this floor")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
                Text("Drag · pinch · twist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
            }

            HStack(spacing: 10) {
                editStat(label: "Moved", value: "\(offsetMeters) m")
                editStat(label: "Rotated", value: String(format: "%.1f°", state.deltaBearing))
                editStat(label: "Scale", value: String(format: "%.2f×", state.scaleMultiplier))
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSaving)

                Button(action: onReset) {
                    Text("Reset")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSaving || !state.isDirty)

                Button(action: onSave) {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Saving…" : "Save")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSaving || !state.isDirty)
                .opacity((isSaving || !state.isDirty) ? 0.6 : 1.0)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.2)))
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    }

    private func editStat(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct BottomRouteCard: View {
    let destination: RouteDestination
    let navigation: NavigationProgress?
    let hasRoute: Bool
    let isNavigating: Bool
    var onDismiss: () -> Void
    var onNavigate: () -> Void
    var onStart: () -> Void
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Capsule()
                    .fill(isNavigating ? Color.white.opacity(0.35) : Color.gray.opacity(0.3))
                    .frame(width: 44, height: 5)
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isNavigating ? .white : .gray)
                            .padding(8)
                            .background(
                                (isNavigating ? Color.white.opacity(0.18) : Color.gray.opacity(0.12)),
                                in: Circle()
                            )
                    }
                }
            }

            if isNavigating, let nav = navigation {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.18), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(nav.distanceLabel)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.white.opacity(0.85))
                            .textCase(.uppercase)
                        Text(nav.instruction)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text("\(nav.remainingSteps) step\(nav.remainingSteps == 1 ? "" : "s") left  •  \(destination.title)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.red, in: Circle())
                    }
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(destination.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                        HStack(spacing: 6) {
                            Circle().fill(hasRoute ? Color.blue : Color.green).frame(width: 8, height: 8)
                            Text(hasRoute ? "Route ready – tap Start to begin" : destination.subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    Button(action: hasRoute ? onStart : onNavigate) {
                        Image(systemName: hasRoute ? "play.fill" : "location.north.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(hasRoute ? Color.green : Color.blue, in: Circle())
                            .shadow(color: (hasRoute ? Color.green : Color.blue).opacity(0.35),
                                    radius: 10, x: 0, y: 6)
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
        }
        .padding(14)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isNavigating ? Color.white.opacity(0.18) : Color.gray.opacity(0.2))
        )
        .shadow(
            color: (isNavigating ? Color.blue.opacity(0.35) : Color.black.opacity(0.12)),
            radius: isNavigating ? 18 : 24,
            x: 0,
            y: isNavigating ? 10 : 12
        )
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isNavigating {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.36, blue: 0.86),
                         Color(red: 0.07, green: 0.27, blue: 0.70)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            Color.white.clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }
}

#Preview("Floor Plan") {
    FloorPlanView()
        .environmentObject(MapNavigationCoordinator())
        .environmentObject(AuthService())
}
