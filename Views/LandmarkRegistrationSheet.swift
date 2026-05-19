//
//  LandmarkRegistrationSheet.swift
//  aau-sw8-ios
//
//  Created by jimpo on 19/05/26.
//

import SwiftUI
import UIKit

struct LandmarkRegistrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DIContainer

    let capturedImage: UIImage
    let onRegistered: ((RegisteredLandmark) -> Void)?

    @State private var name: String = ""
    @State private var selectedSpaceId: String?
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @State private var infoText: String?

    @State private var availableFloors: [FloorSummary] = []
    @State private var selectedFloorId: String?
    @State private var floorRoomsCache: [String: [Room]] = [:]
    @State private var isLoadingFloorRooms: Bool = false

    private let service = LandmarkService()

    private var rooms: [Room] {
        if let floorId = selectedFloorId {
            if let cached = floorRoomsCache[floorId] { return cached }
            let liveFloorId = container.floorPlanService.currentFloorId
            if floorId == liveFloorId { return container.floorPlanService.rooms }
            return []
        }
        return container.floorPlanService.rooms
    }

    private var canSubmit: Bool {
        !isSubmitting
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedSpaceId != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview
                    nameField
                    floorPicker
                    spacePicker
                    if let infoText {
                        Text(infoText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.top, 4)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                    submitButton
                }
                .padding(20)
            }
            .navigationTitle("Register landmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadInitialFloors() }
        }
    }


    private func loadInitialFloors() async {
        guard let buildingId = container.currentBuildingId else { return }
        var floors = container.floorPlanService.floors
        if floors.isEmpty {
            floors = await container.floorPlanService.fetchFloorList(buildingId: buildingId)
        }
        await MainActor.run {
            self.availableFloors = floors
            let live = container.floorPlanService.currentFloorId
            self.selectedFloorId = floors.first(where: { $0.id == live })?.id
                ?? floors.first(where: { $0.floorIndex == 0 })?.id
                ?? floors.first?.id
        }
    }

    private func switchFloor(to floor: FloorSummary) {
        selectedFloorId = floor.id
        selectedSpaceId = nil
        if floorRoomsCache[floor.id] != nil { return }
        Task {
            await MainActor.run { isLoadingFloorRooms = true }
            let fetched = await container.floorPlanService.peekFloorRooms(floorId: floor.id)
            await MainActor.run {
                floorRoomsCache[floor.id] = fetched
                isLoadingFloorRooms = false
            }
        }
    }

    // MARK: - Subviews

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Captured frame")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Image(uiImage: capturedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.yellow.opacity(0.6), lineWidth: 2)
                )
            Text("Make sure the object you want to recognise (e.g. a poster, sign, or placard) fills most of the frame. Texture-rich 2D surfaces work best.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Landmark name")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Joker poster", text: $name)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.sentences)
                .disableAutocorrection(false)
        }
    }

    private var floorPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Floor")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if isLoadingFloorRooms {
                    ProgressView().scaleEffect(0.7)
                }
                Spacer()
                Text("Override if GPS is wrong")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if availableFloors.isEmpty {
                Text("Floor list not loaded — open the Map tab and zoom into a building first.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8))
            } else {
                Menu {
                    ForEach(availableFloors) { floor in
                        Button {
                            switchFloor(to: floor)
                        } label: {
                            HStack {
                                Text(floor.displayName ?? "Floor \(floor.floorIndex)")
                                if selectedFloorId == floor.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedFloorLabel ?? "Choose a floor…")
                            .foregroundStyle(selectedFloorId == nil ? Color.secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var selectedFloorLabel: String? {
        availableFloors.first(where: { $0.id == selectedFloorId })
            .map { $0.displayName ?? "Floor \($0.floorIndex)" }
    }

    private var spacePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attach to space")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if rooms.isEmpty {
                Text("No rooms on this floor — try a different one above.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8))
            } else {
                Menu {
                    ForEach(rooms) { room in
                        Button {
                            selectedSpaceId = room.id
                        } label: {
                            HStack {
                                Text(room.name)
                                if selectedSpaceId == room.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedSpaceLabel ?? "Choose a room…")
                            .foregroundStyle(selectedSpaceId == nil ? Color.secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var selectedSpaceLabel: String? {
        rooms.first(where: { $0.id == selectedSpaceId })?.name
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if isSubmitting { ProgressView().tint(.white) }
                Text(isSubmitting ? "Registering…" : "Register landmark")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? Color.blue : Color.gray.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!canSubmit)
    }

    // MARK: - Action

    private func submit() async {
        guard let spaceId = selectedSpaceId else { return }
        isSubmitting = true
        errorText = nil
        infoText = nil
        defer { isSubmitting = false }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let result = try await service.register(
                image: capturedImage,
                name: trimmed,
                spaceId: spaceId
            )
            infoText = "Registered — ml-vision will pick this up on the next stream connection."
            onRegistered?(result)
            // Auto-dismiss after a short delay so the user sees the
            // success line, but don't block them — Cancel still works.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch let err as LandmarkServiceError {
            errorText = err.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
