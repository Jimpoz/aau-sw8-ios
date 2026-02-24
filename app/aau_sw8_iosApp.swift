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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .tint(.blue600)
        }
    }
}
