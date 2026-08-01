import ParchmentApplication
#if canImport(UIKit)
import UIKit
#else
import Foundation
#endif

public enum ParchmentUIKitModule {
    public static let minimumHitTarget: CGFloat = 44
#if canImport(UIKit)
    public static let preferredSplitStyle = UISplitViewController.Style.doubleColumn
#endif
}
