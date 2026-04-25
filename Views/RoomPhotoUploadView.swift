//
//  RoomPhotoUploadView.swift
//  aau-sw8-ios
//
//  Four-image (N/E/S/W) uploader for the room-summary setup endpoint.
//

import SwiftUI
import PhotosUI

struct RoomPhotoUploadView: View {
    @Environment(\.dismiss) private var dismiss

    private let service = RoomSummaryService()

    @State private var availableRooms: [String] = []
    @State private var selectedRoom: String = ""
    @State private var manualRoomName: String = ""
    @State private var useManualRoom: Bool = false

    @State private var images: [RoomSummaryService.CompassDirection: UIImage] = [:]

    @State private var pendingDirection: RoomSummaryService.CompassDirection? = nil
    @State private var showingSourceDialog = false
    @State private var pickingDirection: RoomSummaryService.CompassDirection? = nil
    @State private var cameraDirection: RoomSummaryService.CompassDirection? = nil
    @State private var pickerItem: PhotosPickerItem? = nil

    @State private var isLoadingRooms = false
    @State private var isUploading = false
    @State private var errorText: String? = nil
    @State private var successText: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    instructionsCard

                    roomPickerCard

                    imagesCard

                    if let err = errorText {
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let ok = successText {
                        Text(ok)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    uploadButton
                }
                .padding(16)
            }
            .background(Color.slate50)
            .navigationTitle("Upload Room Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadRooms() }
            .confirmationDialog(
                pendingDirection.map { "Add \($0.label) photo" } ?? "Add photo",
                isPresented: $showingSourceDialog,
                titleVisibility: .visible
            ) {
                Button("Take Photo") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        cameraDirection = pendingDirection
                    } else {
                        errorText = "Camera is not available on this device."
                    }
                    pendingDirection = nil
                }
                Button("Choose from Library") {
                    pickerItem = nil
                    pickingDirection = pendingDirection
                    pendingDirection = nil
                }
                Button("Cancel", role: .cancel) { pendingDirection = nil }
            }
            .photosPicker(
                isPresented: Binding(
                    get: { pickingDirection != nil },
                    set: { if !$0 { pickingDirection = nil } }
                ),
                selection: $pickerItem,
                matching: .images
            )
            .onChange(of: pickerItem) { _, newItem in
                guard let dir = pickingDirection else { return }
                Task { await handlePickerChange(newItem, direction: dir) }
            }
            .sheet(
                isPresented: Binding(
                    get: { cameraDirection != nil },
                    set: { if !$0 { cameraDirection = nil } }
                )
            ) {
                if let dir = cameraDirection {
                    CameraImagePicker { image in
                        if let image { images[dir] = image }
                        cameraDirection = nil
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: - Subviews

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.slate700)
            Text("Stand in the center of the room and take four photos, one per compass direction. Upload them clockwise: North → East → South → West. The server runs object detection on all four and stores the result on the room.")
                .font(.system(size: 13))
                .foregroundStyle(Color.slate600)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.slate100))
    }

    private var roomPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Room")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.slate700)

            if isLoadingRooms {
                HStack { ProgressView(); Text("Loading rooms…").font(.system(size: 13)).foregroundStyle(Color.slate500) }
            } else if availableRooms.isEmpty {
                Text("No rooms returned from the server — enter a room name manually below.")
                    .font(.system(size: 12)).foregroundStyle(Color.slate500)
            } else {
                Picker("Room", selection: $selectedRoom) {
                    ForEach(availableRooms, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(useManualRoom)
            }

            Toggle("Type a room name manually", isOn: $useManualRoom)
                .font(.system(size: 13))
                .foregroundStyle(Color.slate600)

            if useManualRoom {
                TextField("e.g. A101", text: $manualRoomName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.slate100))
    }

    private var imagesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.slate700)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(RoomSummaryService.CompassDirection.allCases) { dir in
                    imageTile(for: dir)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.slate100))
    }

    private func imageTile(for dir: RoomSummaryService.CompassDirection) -> some View {
        Button {
            pendingDirection = dir
            showingSourceDialog = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.slate100)
                        .frame(height: 110)
                    if let img = images[dir] {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.slate500)
                            Text("Tap to add")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.slate500)
                        }
                    }
                }
                Text(dir.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.slate700)
            }
        }
        .buttonStyle(.plain)
    }

    private var uploadButton: some View {
        Button {
            Task { await upload() }
        } label: {
            HStack {
                if isUploading { ProgressView().tint(.white) }
                Text(isUploading ? "Uploading…" : "Upload & Analyze")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canUpload ? Color.blue500 : Color.slate500.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!canUpload || isUploading)
    }

    // MARK: - Logic

    private var resolvedRoomName: String {
        (useManualRoom ? manualRoomName : selectedRoom).trimmingCharacters(in: .whitespaces)
    }

    private var canUpload: Bool {
        !resolvedRoomName.isEmpty && RoomSummaryService.CompassDirection.allCases.allSatisfy { images[$0] != nil }
    }

    private func loadRooms() async {
        isLoadingRooms = true
        defer { isLoadingRooms = false }
        do {
            let names = try await service.listRooms()
            availableRooms = names
            if selectedRoom.isEmpty, let first = names.first { selectedRoom = first }
        } catch {
            errorText = "Could not load rooms: \(error.localizedDescription)"
        }
    }

    private func handlePickerChange(
        _ item: PhotosPickerItem?,
        direction dir: RoomSummaryService.CompassDirection
    ) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                images[dir] = ui
            }
        } catch {
            errorText = "Could not load image: \(error.localizedDescription)"
        }
        pickingDirection = nil
        pickerItem = nil
    }

    private func upload() async {
        errorText = nil
        successText = nil
        isUploading = true
        defer { isUploading = false }
        do {
            let result = try await service.uploadRoomPhotos(
                roomName: resolvedRoomName,
                images: images
            )
            let counts = (result.room_object_counts ?? [:])
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            successText = "Saved to \(result.room_name). Detected — \(counts.isEmpty ? "no objects" : counts)."
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview("RoomPhotoUpload") { RoomPhotoUploadView() }

struct CameraImagePicker: UIViewControllerRepresentable {
    let onResult: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (UIImage?) -> Void
        init(onResult: @escaping (UIImage?) -> Void) { self.onResult = onResult }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.originalImage] as? UIImage)
            onResult(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onResult(nil)
        }
    }
}
