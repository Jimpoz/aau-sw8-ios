//
//  MapTabView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import SwiftUI

struct MapTabView: View {
    var body: some View {
        FloorPlanView()
    }
}

#Preview("MapTab") { MapTabView().environmentObject(AuthService()) }
