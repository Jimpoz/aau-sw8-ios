//
//  OrganizationPickerView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import SwiftUI

struct OrganizationPickerView: View {
    let title: String
    let subtitle: String
    /// Called when the user picks an organization + campus.
    let onSelect: (OrganizationDTO, CampusDTO) -> Void

    @StateObject private var orgs = OrganizationService()
    @State private var selectedOrg: OrganizationDTO?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if orgs.isLoading && orgs.organizations.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading organizations…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.slate500)
                    }
                    .padding(14)
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

                if selectedOrg == nil {
                    organizationsList
                } else if let org = selectedOrg {
                    selectedOrganizationHeader(org)
                    campusesList(for: org)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.slate50)
        .task { await orgs.loadOrganizations() }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.slate800)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Color.slate500)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var organizationsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Organizations")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.slate600)
                .padding(.horizontal, 16)

            VStack(spacing: 10) {
                ForEach(orgs.organizations) { org in
                    Button {
                        selectedOrg = org
                        Task { await orgs.loadCampuses(forOrganization: org.id) }
                    } label: {
                        OrgRow(org: org)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                if !orgs.isLoading && orgs.organizations.isEmpty && orgs.errorText == nil {
                    Text("No organizations are configured on the server.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.slate500)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private func selectedOrganizationHeader(_ org: OrganizationDTO) -> some View {
        HStack {
            Button {
                selectedOrg = nil
                orgs.campuses = []
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    Text("Organizations")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.blue600)
            }

            Spacer()

            Text(org.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.slate700)
        }
        .padding(.horizontal, 16)
    }

    private func campusesList(for org: OrganizationDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Campuses")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.slate600)
                .padding(.horizontal, 16)

            if orgs.isLoading && orgs.campuses.isEmpty {
                HStack { ProgressView(); Text("Loading campuses…") }
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 10) {
                ForEach(orgs.campuses) { campus in
                    Button {
                        onSelect(org, campus)
                    } label: {
                        CampusRow(campus: campus)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                if !orgs.isLoading && orgs.campuses.isEmpty {
                    Text("This organization has no campuses yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.slate500)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct OrgRow: View {
    let org: OrganizationDTO

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue100)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "building.2.fill")
                        .foregroundStyle(Color.blue600)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(org.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.slate800)
                if let desc = org.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.slate500)
                        .lineLimit(2)
                } else if let kind = org.entity_type {
                    Text(kind.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.slate500)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.slate400)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.slate100))
    }
}

private struct CampusRow: View {
    let campus: CampusDTO

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue50)
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
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.slate400)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.slate100))
    }
}

#Preview("OrgPicker") {
    OrganizationPickerView(
        title: "Choose a campus",
        subtitle: "Pick an organization, then a campus to open the map.",
        onSelect: { _, _ in }
    )
}
