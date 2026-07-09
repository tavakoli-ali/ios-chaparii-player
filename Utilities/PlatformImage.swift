//
// PlatformImage
//
// Cross-platform aliases so shared code can handle images/colors without
// importing AppKit directly. macOS uses NS*, iOS uses UI*.
//

import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
#else
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
#endif

extension Color {
    /// Builds a SwiftUI Color from the platform color type.
    init(platform color: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: color)
        #else
        self.init(uiColor: color)
        #endif
    }
}
