import SwiftUI

enum ProfileAvatar: String, CaseIterable, Identifiable {
    case person = "person.fill"
    case mountain = "mountain.2.fill"
    case moon = "moon.stars.fill"
    case bolt = "bolt.fill"

    static let storageKey = "strap.profile.avatar.v1"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .person: "Person"
        case .mountain: "Mountain"
        case .moon: "Moon"
        case .bolt: "Bolt"
        }
    }
}

struct ProfileAvatarView: View {
    @AppStorage(ProfileAvatar.storageKey) private var avatar: ProfileAvatar = .person
    let size: CGFloat

    var body: some View {
        Image(systemName: avatar.rawValue)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Color.appBG)
            .frame(width: size, height: size)
            .background(Color(hex: 0x72CED1), in: Circle())
            .accessibilityHidden(true)
    }
}

struct ProfileView: View {
    static let nameKey = "strap.profile.displayName.v1"
    @AppStorage(ProfileView.nameKey) private var displayName = ""
    @AppStorage(ProfileAvatar.storageKey) private var avatar: ProfileAvatar = .person
    @State private var draftName = ""
    @State private var draftAvatar: ProfileAvatar = .person
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Display name", text: $draftName)
                    .textContentType(.nickname)
                    .accessibilityIdentifier("profile.displayName")
                Picker("Avatar", selection: $draftAvatar) {
                    ForEach(ProfileAvatar.allCases) { option in
                        Label(option.title, systemImage: option.rawValue).tag(option)
                    }
                }
            } header: {
                Text("Personal profile")
            } footer: {
                Text("Your name and avatar are stored on this device.")
            }

            Section {
                NavigationLink("Health & Activity Settings") { SettingsView() }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    displayName = String(draftName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                    avatar = draftAvatar
                    dismiss()
                }
            }
        }
        .onAppear {
            draftName = displayName
            draftAvatar = avatar
        }
    }
}
