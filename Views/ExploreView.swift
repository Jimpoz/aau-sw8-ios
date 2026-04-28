//
//  ExploreView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//
//  Browse organizations → campuses → buildings, fetched live from the spatial backend.
//

import SwiftUI

struct ExploreView: View {
    @State private var selectedOrg: OrganizationDTO?
    @State private var selectedCampus: CampusDTO?

    var body: some View {
        if let org = selectedOrg, let campus = selectedCampus {
            ExploreCampusView(org: org, campus: campus) {
                selectedOrg = nil
                selectedCampus = nil
            }
        } else {
            OrganizationPickerView(
                title: "Explore",
                subtitle: "Pick an organization, then a campus to browse its buildings."
            ) { org, campus in
                selectedOrg = org
                selectedCampus = campus
            }
        }
    }
}

private struct ExploreCampusView: View {
    let org: OrganizationDTO
    let campus: CampusDTO
    let onChangeCampus: () -> Void

    @StateObject private var orgs = OrganizationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if orgs.isLoading && orgs.buildings.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading buildings…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.slate500)
                    }
                    .padding(.horizontal, 16)
                }

                if let err = orgs.errorText {
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                }

                campusSection
                buildingsSection
            }
            .padding(.bottom, 24)
        }
        .background(Color.slate50)
        .task { await orgs.loadBuildings(forCampus: campus.id) }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explore")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.slate800)
                Text(org.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.slate500)
            }
            Spacer()
            Button(action: onChangeCampus) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("Switch")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(Color.blue600, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var campusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Campus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.slate600)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue100)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "map.fill")
                            .foregroundStyle(Color.blue600)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(campus.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.slate800)
                    if let desc = campus.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.slate500)
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.slate100))
            .padding(.horizontal, 16)
        }
    }

    private var buildingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Buildings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.slate600)
                Spacer()
                Text("\(orgs.buildings.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.slate500)
            }
            .padding(.horizontal, 16)

            if !orgs.isLoading && orgs.buildings.isEmpty && orgs.errorText == nil {
                Text("This campus has no buildings yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.slate500)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 10) {
                ForEach(orgs.buildings) { building in
                    BuildingRow(building: building)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct BuildingRow: View {
    let building: BuildingDTO

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue100)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "building.columns.fill")
                        .foregroundStyle(Color.blue600)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(building.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.slate800)
                let parts: [String] = [
                    building.short_name.map { "Code \($0)" },
                    building.address,
                    building.floor_count.map { "\($0) floor\($0 == 1 ? "" : "s")" }
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.slate500)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "location.north.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.blue600)
                .padding(10)
                .background(Color.blue50, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.slate100))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

#Preview("Explore") { ExploreView() }
