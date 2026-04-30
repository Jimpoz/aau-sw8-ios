//
//  VisibleCampusPickerView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 30/04/26.
//
//

import SwiftUI

struct VisibleCampusPickerView: View {
    let title: String
    let subtitle: String
    let onSelect: (VisibleCampusDTO) -> Void

    @EnvironmentObject private var authService: AuthService
    @StateObject private var orgs = OrganizationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if orgs.isLoading && orgs.visibleCampuses.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading campuses…")
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

                campusList
            }
            .padding(.bottom, 24)
        }
        .background(Color.slate50)
        .task { await orgs.loadVisibleCampuses() }
    }

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

    private var myOrgId: String? { authService.principal?.organizationId }

    private var campusList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Campuses")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.slate600)
                .padding(.horizontal, 16)

            VStack(spacing: 10) {
                ForEach(orgs.visibleCampuses) { campus in
                    Button {
                        onSelect(campus)
                    } label: {
                        VisibleCampusRow(
                            campus: campus,
                            isFromMyOrg: myOrgId != nil && campus.organization_id == myOrgId
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                if !orgs.isLoading && orgs.visibleCampuses.isEmpty && orgs.errorText == nil {
                    Text("No campuses are visible to you yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.slate500)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct VisibleCampusRow: View {
    let campus: VisibleCampusDTO
    let isFromMyOrg: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue50)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "map.fill")
                        .foregroundStyle(Color.blue600)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(campus.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.slate800)

                HStack(spacing: 6) {
                    if let orgName = campus.organization_name, !orgName.isEmpty {
                        Text(orgName)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.slate500)
                            .lineLimit(1)
                    }
                    if isFromMyOrg {
                        Text("Your org")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.blue600)
                            .background(Color.blue100, in: Capsule())
                    } else if campus.is_public {
                        Text("Public")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.slate600)
                            .background(Color.slate100, in: Capsule())
                    }
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

#Preview("VisibleCampusPicker") {
    VisibleCampusPickerView(
        title: "Choose a campus",
        subtitle: "Pick a campus to open the floor map.",
        onSelect: { _ in }
    )
    .environmentObject(AuthService())
}
