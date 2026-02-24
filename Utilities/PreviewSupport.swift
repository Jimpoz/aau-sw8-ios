//
//  PreviewSupport.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//


import Foundation

enum PreviewSupport {
    static var isRunning: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
