// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

/// This type should match the `ImageFormat` type in `SessionUtilitiesKit`
public enum SUIKImageFormat {
    case unknown
    case png
    case gif
    case tiff
    case jpeg
    case bmp
    case webp
    
    var nullIfUnknown: SUIKImageFormat? {
        switch self {
            case .unknown: return nil
            default: return self
        }
    }
}
