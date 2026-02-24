//
//  ExploreView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI

struct ExploreView: View {
    @State private var category: String = "All"
    // The list of the categories will depend on the type of building
    private let categories = ["All", "Food", "Shopping", "Services", "Transport"]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // BuildingType
                Text("Explore the [BuildingType]")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.slate800)
                    .padding(.top, 6)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { cat in
                            Chip(title: cat, selected: cat == category) {
                                category = cat
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .background(.white)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.slate100), alignment: .bottom)

            // Mock "data"
            ScrollView {
                VStack(spacing: 12) {
                    // for each will be dynamic based on the amount of catefories within the building
                    ForEach(0..<5, id: \.self) { _ in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.blue100)
                                .frame(width: 44, height: 44)
                                .overlay(Image(systemName: "location.fill.viewfinder").foregroundStyle(Color.blue600))
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 6).fill(Color.slate200).frame(width: 160, height: 14)
                                RoundedRectangle(cornerRadius: 6).fill(Color.slate100).frame(width: 110, height: 10)
                            }
                            Spacer()
                            Button {
                                // To add navigation function
                            } label: {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.blue600)
                                    .padding(10)
                                    .background(Color.blue50, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.slate100))
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                        .padding(.horizontal, 16)
                    }

                    Text("Connect your indoor data source to populate results.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.slate500)
                        .padding(.top, 6)
                }
                .padding(.top, 12)
                .background(Color.slate50)
            }
        }
        .background(Color.slate50)
    }
}

#Preview("Explore") { ExploreView() }
