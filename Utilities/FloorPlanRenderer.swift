//
//  FloorPlanRenderer.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI

/// Canvas-based floor plan renderer - draws polygons and room shapes
struct FloorPlanRenderer: View {
    let rooms: [Room]
    let userLocation: CGPoint?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    
    var body: some View {
        Canvas { context in
            // Draw rooms
            for room in rooms {
                drawRoom(room: room, in: &context)
            }
            
            // Draw user location if available
            if let userLoc = userLocation {
                drawUserLocation(at: userLoc, in: &context)
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = value
                }
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = value.translation
                }
        )
    }
    
    private func drawRoom(room: Room, in context: inout GraphicsContext) {
        guard let polygon = room.polygon, polygon.count > 2 else { return }
        
        // Create path from polygon points
        var path = Path()
        let firstPoint = transform(polygon[0])
        path.move(to: firstPoint)
        
        for i in 1..<polygon.count {
            let point = transform(polygon[i])
            path.addLine(to: point)
        }
        path.closeSubpath()
        
        // Fill color based on room type
        let fillColor = colorForRoomType(room.type)
        
        // Draw filled room
        context.fill(
            path,
            with: .color(fillColor.withAlphaComponent(0.7))
        )
        
        // Draw border
        context.stroke(
            path,
            with: .color(.black.withAlphaComponent(0.3)),
            lineWidth: 2
        )
        
        // Draw room label at centroid
        if let centroid = room.centroid {
            let labelPoint = transform(centroid)
            var stringContext = context
            stringContext.translateBy(x: labelPoint.x, y: labelPoint.y)
            
            let attributedString = AttributedString(room.name)
            let resolved = stringContext.resolveSymbolImage(for: Text(attributedString))
            
            stringContext.draw(
                Text(room.name)
                    .font(.caption2)
                    .foregroundColor(.black),
                at: labelPoint,
                anchor: .center
            )
        }
    }
    
    private func drawUserLocation(at point: CGPoint, in context: inout GraphicsContext) {
        let transformedPoint = transform(point)
        
        // Draw circle for user location
        var circlePath = Path()
        circlePath.addEllipse(in: CGRect(
            x: transformedPoint.x - 8,
            y: transformedPoint.y - 8,
            width: 16,
            height: 16
        ))
        
        context.fill(circlePath, with: .color(.blue))
        
        // Draw border
        context.stroke(
            circlePath,
            with: .color(.white),
            lineWidth: 2
        )
    }
    
    private func transform(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: point.x * scale + offset.width,
            y: point.y * scale + offset.height
        )
    }
    
    private func colorForRoomType(_ type: RoomType) -> Color {
        switch type {
        case .classroom:
            return Color(red: 0.9, green: 0.95, blue: 1.0)
        case .office:
            return Color(red: 0.95, green: 0.95, blue: 0.9)
        case .meetingRoom:
            return Color(red: 0.95, green: 0.9, blue: 0.95)
        case .restroom:
            return Color(red: 0.9, green: 1.0, blue: 0.9)
        case .restaurant:
            return Color(red: 1.0, green: 0.95, blue: 0.85)
        case .shop:
            return Color(red: 1.0, green: 0.98, blue: 0.9)
        case .hallway:
            return Color(red: 0.98, green: 0.98, blue: 0.98)
        case .exit, .entrance:
            return Color(red: 0.9, green: 0.9, blue: 1.0)
        default:
            return Color(red: 0.95, green: 0.95, blue: 0.95)
        }
    }
}

#Preview {
    FloorPlanRenderer(
        rooms: [
            Room(
                id: "room1",
                name: "Room 101",
                type: .classroom,
                centroid: CGPoint(x: 100, y: 100),
                polygon: [
                    CGPoint(x: 50, y: 50),
                    CGPoint(x: 150, y: 50),
                    CGPoint(x: 150, y: 150),
                    CGPoint(x: 50, y: 150)
                ],
                metadata: nil
            ),
            Room(
                id: "room2",
                name: "Room 102",
                type: .office,
                centroid: CGPoint(x: 300, y: 100),
                polygon: [
                    CGPoint(x: 200, y: 50),
                    CGPoint(x: 350, y: 50),
                    CGPoint(x: 350, y: 150),
                    CGPoint(x: 200, y: 150)
                ],
                metadata: nil
            )
        ],
        userLocation: CGPoint(x: 100, y: 100)
    )
}
