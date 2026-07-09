import Foundation

// Security-scoped bookmarks are macOS-only; iOS (File Sharing / Documents) uses
// plain bookmarks. These give call sites one platform-correct option set.
extension URL.BookmarkCreationOptions {
    static var appSecurityScope: URL.BookmarkCreationOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }
}

extension URL.BookmarkResolutionOptions {
    static var appSecurityScope: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }
}
