import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System Default"
        case .english: "English"
        case .korean: "Korean"
        case .simplifiedChinese: "Simplified Chinese"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            Locale.autoupdatingCurrent
        case .english, .korean, .simplifiedChinese:
            Locale(identifier: rawValue)
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System Default"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum UserGender: String, CaseIterable, Identifiable {
    case notSpecified
    case female
    case male
    case nonBinary
    case preferNotToSay

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .notSpecified: "Not Specified"
        case .female: "Female"
        case .male: "Male"
        case .nonBinary: "Non-binary"
        case .preferNotToSay: "Prefer Not to Say"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("settings.language") private var languageRawValue = AppLanguage.system.rawValue
    @AppStorage("settings.theme") private var themeRawValue = AppTheme.system.rawValue
    @AppStorage("settings.gender") private var genderRawValue = UserGender.notSpecified.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    NavigationLink {
                        AccountView()
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }
                }

                Section("Preferences") {
                    Picker("Language", selection: $languageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }

                    Picker("Theme", selection: $themeRawValue) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }

                    Picker("Gender", selection: $genderRawValue) {
                        ForEach(UserGender.allCases) { gender in
                            Text(gender.title).tag(gender.rawValue)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AccountView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Account", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("Account features will be available in a future update.")
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
