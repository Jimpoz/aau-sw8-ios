//
//  AssistantView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//
import SwiftUI

struct AssistantView: View {
    @StateObject private var vm = AssistantViewModel()
    @EnvironmentObject var container: DIContainer

    var body: some View {
        VStack(spacing: 0) {
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(Color.success).frame(width: 8, height: 8)
                        .shadow(color: .success.opacity(0.6), radius: 4, x: 0, y: 0)
                    Text("Virtual Assistant")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.slate800)
                    Spacer()
                }
                Text("Online • AI Powered Guide")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.slate500)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.white)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.slate100), alignment: .bottom)

            // Messages
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 10, alignment: .leading) {
                        ForEach(vm.messages) { msg in
                            HStack {
                                if msg.role == .assistant {
                                    Text(msg.text)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.slate700)
                                        .padding(12)
                                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.slate100)
                                        )
                                        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                } else {
                                    Spacer(minLength: 40)

                                    Text(msg.text)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.white)
                                        .padding(12)
                                        .background(Color.blue600, in: RoundedRectangle(cornerRadius: 16))
                                        .shadow(color: Color.blue600.opacity(0.25), radius: 10, x: 0, y: 6)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                            .padding(.horizontal, 16)
                            .id(msg.id)
                        }
                        
                        // Loading indicator
                        if vm.isLoading {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { index in
                                    Circle()
                                        .fill(Color.slate400)
                                        .frame(width: 8, height: 8)
                                        .scaleEffect(1.0)
                                        .animation(
                                            Animation.easeInOut(duration: 0.6)
                                                .repeatForever()
                                                .delay(Double(index) * 0.15),
                                            value: vm.isLoading
                                        )
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 8)
                    .onChange(of: vm.messages.count) { _, _ in
                        if let lastMessage = vm.messages.last {
                            reader.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.slate50)

            // Composer
            HStack(spacing: 8) {
                HStack {
                    TextField("Ask anything…", text: $vm.input)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.slate800)
                        .textInputAutocapitalization(.sentences)
                        .disabled(vm.isLoading)
                    
                    Button { /* To add a mic function for voice texting */ } label: {
                        Image(systemName: "mic")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.slate500)
                    }
                    .disabled(vm.isLoading)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.slate100, in: Capsule())

                Button(action: vm.send) {
                    if vm.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
                .background(Color.blue600, in: Circle())
                .shadow(color: .blue600.opacity(0.35), radius: 8, x: 0, y: 5)
                .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.white)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.slate100), alignment: .top)
        }
        .background(Color.slate50)
        .onAppear {
            vm.configure(with: container)
        }
    }
}

#Preview("Assistant") { 
    AssistantView()
        .environmentObject(DIContainer())
}
