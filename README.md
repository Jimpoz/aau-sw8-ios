# aau-sw8-ios

SwiftUI client for the Ariadne indoor navigation platform. Talks to the spatial backend's gateway (`/api/v1/*` on `:8080`) for everything, plus the real-time vision service (`/api/v1/ml-vision/*`) for the camera feature.

## What's in the app

| Tab / view             | What it does                                                                                  |
|------------------------|-----------------------------------------------------------------------------------------------|
| Floor plan             | Renders a floor's polygons + centroids fetched from `/api/v1/floors/{id}/display`             |
| Navigation             | Calls `/api/v1/navigate?from=&to=&accessible_only=` and overlays the route on the floor plan  |
| Assistant              | Chat UI talking to `/api/v1/assistant/chat` (LLM + RAG over the graph)                        |
| Camera                 | Live AR overlay; streams frames to `WS /api/v1/ml-vision/ws/stream/{facility_id}`             |
| Room photo upload      | Four-direction (N/E/S/W) uploader for `/api/v1/room-summary/room-objects/setup`               |

## Build / run

1. Open `aau-sw8-ios/` in Xcode.
2. Create a file named `AppSecrets.swift` next to the rest of the Swift sources (it's in `.gitignore`):

   ```swift
   enum AppSecrets {
       static let backendURL = "https://your-gateway.example.com"
       static let apiSecret  = "your-x-api-key"
   }
   ```

   `backendURL` should point at the spatial backend's middleware (`:8080` in the compose stack, or your reverse-proxied public URL). Both keys are read by every networking service in [Services/](Services/).
3. Pick a real device for the camera + WebSocket features (the simulator can't use the rear camera).
4. ⌘R.

## Layout

```
aau-sw8-ios/
├── app/                  Entry point (aau_sw8_iosApp.swift), root ContentView, Assets
├── Views/                SwiftUI screens (FloorPlanView, AssistantView, CameraView, RoomPhotoUploadView, ...)
├── ViewModels/           @MainActor view models (FloorPlanViewModel, AssistantViewModel, CameraViewModel)
├── Services/             API clients — one per backend surface
│   ├── FloorPlanService.swift     /floors/{id}/display, /floors/{id}/geometry, /floors/{id}/map-overlay
│   ├── NavigationService.swift    /navigate, /navigate/refresh-graph
│   ├── AssistantService.swift     /assistant/chat
│   ├── RoomSummaryService.swift   /room-summary/* (incl. room-objects/setup)
│   ├── VisionStreamingService.swift  WS /ml-vision/ws/stream/{facility_id}
│   ├── LocationManager.swift      CoreLocation wrapper
│   ├── DetectionBox.swift         Decoded stream-frame detection model
│   ├── DIContainer.swift          Lightweight service container injected via @Environment
│   └── Protocols.swift            Service protocols for tests/previews
├── Models/DataModels.swift        Decodable shapes mirroring the backend
└── Utilities/                     Shared helpers, color extensions, etc.
```

## Conventions

- Every networking call sets `X-Api-Key: AppSecrets.apiSecret` — the gateway rejects requests without it.
- Service signatures use `async`/`await`; SwiftUI surfaces wrap them in `Task { ... }` from the relevant view model.
- The room photo uploader takes images either from the camera (`UIImagePickerController` via `CameraImagePicker`) or the photo library (`PhotosPicker`); both flows feed into the same `RoomSummaryService.uploadRoomPhotos`.
