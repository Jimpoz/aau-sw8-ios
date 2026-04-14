//
//  aau_sw8_iosApp.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI

@main
struct aau_sw8_iosApp: App {
    @StateObject private var container = DIContainer()
    @StateObject private var themeSettings = ThemeSettings()

    init() {
        // Darker grey icons + labels in the TabBar (unselected).
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.white

        let unselected = UIColor.systemGray2
        let selected = UIColor(Color.blue600)

        appearance.stackedLayoutAppearance.normal.iconColor = unselected
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselected]
        appearance.stackedLayoutAppearance.selected.iconColor = selected
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selected]

        // Apply to all layout styles for safety.
        appearance.inlineLayoutAppearance = appearance.stackedLayoutAppearance
        appearance.compactInlineLayoutAppearance = appearance.stackedLayoutAppearance

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .environmentObject(themeSettings)
                .preferredColorScheme(themeSettings.isDarkMode ? .dark : .light)
                .tint(.blue600)
        }
    }
}
