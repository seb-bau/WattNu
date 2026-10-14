import Foundation
import Combine
import SwiftUI

@MainActor
final class LocalAppSettings: ObservableObject {
    @Published var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Keys.baseURLString)
        }
    }

    @Published var appearanceMode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
        }
    }

    var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var preferredColorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }

    init() {
        self.baseURLString = UserDefaults.standard.string(forKey: Keys.baseURLString) ?? "https://public.mach-ma.app"
        self.appearanceMode = AppAppearanceMode(rawValue: UserDefaults.standard.string(forKey: Keys.appearanceMode) ?? "system") ?? .system
    }

    private enum Keys {
        static let baseURLString = "baseURLString"
        static let appearanceMode = "appearanceMode"
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Hell"
        case .dark:
            return "Dunkel"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
