import Foundation
import Combine

@MainActor
final class LocalAppSettings: ObservableObject {
    @Published var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Keys.baseURLString)
        }
    }

    var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    init() {
        self.baseURLString = UserDefaults.standard.string(forKey: Keys.baseURLString) ?? "http://127.0.0.1:5000"
    }

    private enum Keys {
        static let baseURLString = "baseURLString"
    }
}
