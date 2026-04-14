//
//  ThemeSettings.swift
//  aau-sw8-ios
//

import SwiftUI
import Combine

@MainActor
final class ThemeSettings: ObservableObject {
    @AppStorage("theme.isDarkMode") var isDarkMode: Bool = false {
        willSet { objectWillChange.send() }
    }
}

