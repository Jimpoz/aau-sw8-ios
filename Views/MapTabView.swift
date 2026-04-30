//
//  MapTabView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import SwiftUI

struct MapTabView: View {
    @State private var selectedCampus: VisibleCampusDTO?

    var body: some View {
        if let campus = selectedCampus {
            ZStack(alignment: .topTrailing) {
                FloorPlanView(campusId: campus.id)

                Button {
                    selectedCampus = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("Switch")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.55), in: Capsule())
                }
                .padding(.top, 70)
                .padding(.trailing, 16)
            }
        } else {
            VisibleCampusPickerView(
                title: "Choose a campus",
                subtitle: "Pick a campus from your organization or a public location."
            ) { campus in
                selectedCampus = campus
            }
        }
    }
}

#Preview("MapTab") { MapTabView().environmentObject(AuthService()) }
