//
//  MapTabView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import SwiftUI

struct MapTabView: View {
    @State private var selectedOrg: OrganizationDTO?
    @State private var selectedCampus: CampusDTO?

    var body: some View {
        if selectedOrg != nil, selectedCampus != nil {
            ZStack(alignment: .topTrailing) {
                FloorPlanView()

                Button {
                    selectedOrg = nil
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
            OrganizationPickerView(
                title: "Choose a campus",
                subtitle: "Pick an organization and a campus to open the floor map."
            ) { org, campus in
                selectedOrg = org
                selectedCampus = campus
            }
        }
    }
}

#Preview("MapTab") { MapTabView() }
