//
//  Chip.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI

private func adaptive(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
    Color(uiColor: UIColor { trait in
        let (r, g, b) = trait.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
    })
}

extension Color {
    // Slate — flipped in dark mode so 50 (lightest in light) becomes near-black,
    // 800 (darkest in light) becomes near-white, etc.
    static let slate50   = adaptive(light: (248,250,252), dark: (15, 23, 42))
    static let slate100  = adaptive(light: (241,245,249), dark: (30, 41, 59))
    static let slate200  = adaptive(light: (226,232,240), dark: (51, 65, 85))
    static let slate300  = adaptive(light: (203,213,225), dark: (71, 85, 105))
    static let slate400  = adaptive(light: (148,163,184), dark: (148,163,184))
    static let slate500  = adaptive(light: (100,116,139), dark: (148,163,184))
    static let slate600  = adaptive(light: (71, 85, 105), dark: (203,213,225))
    static let slate700  = adaptive(light: (51, 65, 85),  dark: (226,232,240))
    static let slate800  = adaptive(light: (30, 41, 59),  dark: (241,245,249))
    static let slate900  = adaptive(light: (15, 23, 42),  dark: (248,250,252))

    // Blue — kept consistent; small darken in dark mode to avoid glow.
    static let blue50    = adaptive(light: (239,246,255), dark: (29, 51,  98))
    static let blue100   = adaptive(light: (219,234,254), dark: (37, 60,  120))
    static let blue200   = adaptive(light: (191,219,254), dark: (47, 82,  150))
    static let blue300   = adaptive(light: (147,197,253), dark: (96, 165, 250))
    static let blue400   = adaptive(light: (96, 165,250), dark: (96, 165, 250))
    static let blue500   = adaptive(light: (59, 130,246), dark: (96, 165, 250))
    static let blue600   = adaptive(light: (37, 99, 235), dark: (59, 130, 246))
    static let blue700   = adaptive(light: (29, 78, 216), dark: (37, 99,  235))

    // Status
    static let success   = Color(red: 34/255,  green: 197/255, blue: 94/255)

    // Card surface that reads as white in light mode and dark slate in dark mode.
    // Use this in place of hardcoded `.white` for any card background that
    // should adapt to the user's color scheme.
    static let cardSurface = adaptive(light: (255,255,255), dark: (24, 33,  54))
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
