import Foundation

enum BuildInfo {
    static var revision: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "StrapBuildRevision") as? String,
              value.count >= 7, value.allSatisfy({ $0.isHexDigit }) else { return "local" }
        return String(value.prefix(7))
    }
}
