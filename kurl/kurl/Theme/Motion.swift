import SwiftUI
import UIKit

enum Motion {
    static let micro = Animation.smooth(duration: 0.2)
    static let move = Animation.smooth(duration: 0.28)
    static let stage = Animation.smooth(duration: 0.45)

    static func animation(
        _ animation: Animation, reduced: Bool = UIAccessibility.isReduceMotionEnabled
    ) -> Animation? {
        reduced ? nil : animation
    }
}

func withMotion<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.animation(animation), body)
}
