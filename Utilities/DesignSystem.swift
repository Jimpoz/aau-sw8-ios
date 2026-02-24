//
//  Chip.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI

// Color Palette for a somewhat decent looking UI
extension Color {
    // Slate
    static let slate50   = Color(red: 248/255, green: 250/255, blue: 252/255)
    static let slate100  = Color(red: 241/255, green: 245/255, blue: 249/255)
    static let slate200  = Color(red: 226/255, green: 232/255, blue: 240/255)
    static let slate300  = Color(red: 203/255, green: 213/255, blue: 225/255)
    static let slate400  = Color(red: 148/255, green: 163/255, blue: 184/255)
    static let slate500  = Color(red: 100/255, green: 116/255, blue: 139/255)
    static let slate600  = Color(red: 71/255,  green: 85/255,  blue: 105/255)
    static let slate700  = Color(red: 51/255,  green: 65/255,  blue: 85/255)
    static let slate800  = Color(red: 30/255,  green: 41/255,  blue: 59/255)
    static let slate900  = Color(red: 15/255,  green: 23/255,  blue: 42/255)

    // Blue
    static let blue50    = Color(red: 239/255, green: 246/255, blue: 255/255)
    static let blue100   = Color(red: 219/255, green: 234/255, blue: 254/255)
    static let blue200   = Color(red: 191/255, green: 219/255, blue: 254/255)
    static let blue300   = Color(red: 147/255, green: 197/255, blue: 253/255)
    static let blue400   = Color(red: 96/255,  green: 165/255, blue: 250/255)
    static let blue500   = Color(red: 59/255,  green: 130/255, blue: 246/255)
    static let blue600   = Color(red: 37/255,  green: 99/255,  blue: 235/255)
    static let blue700   = Color(red: 29/255,  green: 78/255,  blue: 216/255)

    // Status
    static let success   = Color(red: 34/255,  green: 197/255, blue: 94/255)
}

// Effects
enum DS {
    static let corner: CGFloat = 20

    static func cardBackground() -> some ShapeStyle {
        Color.white
    }

    static func cardShadow() -> some ViewModifier {
        ShadowModifier()
    }

    static func blurBackdrop() -> some ViewModifier {
        BlurCardModifier()
    }

    private struct ShadowModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 10)
        }
    }

    private struct BlurCardModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.corner))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.corner)
                        .stroke(Color.slate200, lineWidth: 1)
                )
        }
    }
}

// Reusable UI
struct Chip: View {
    let title: String
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.slate600)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.slate800 : Color.slate100)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// Dotted background
struct DottedBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                let spacing: CGFloat = 20
                let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.2, height: 1.2))
                let cols = Int(size.width / spacing) + 2
                let rows = Int(size.height / spacing) + 2
                for i in 0..<cols {
                    for j in 0..<rows {
                        var t = CGAffineTransform(translationX: CGFloat(i) * spacing,
                                                  y: CGFloat(j) * spacing)
                        let p = dot.applying(t)
                        ctx.fill(p, with: .color(Color.slate500.opacity(0.10)))

                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
