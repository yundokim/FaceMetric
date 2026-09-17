//
//  FaceMetricApp.swift
//  FaceMetric
//
//  Created by Yundo Kim on 9/16/26.
//

import SwiftUI

@main
struct FaceMetricApp: App {
    @AppStorage("settings.language") private var languageRawValue = AppLanguage.system.rawValue
    @AppStorage("settings.theme") private var themeRawValue = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, selectedLanguage.locale)
                .preferredColorScheme(selectedTheme.colorScheme)
        }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .system
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }
}
