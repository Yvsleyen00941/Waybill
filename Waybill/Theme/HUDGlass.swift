import SwiftUI

/// The material behind every floating interface panel, in one place.
enum HUDGlass {
    /// Developer switch (`-flatGlass YES`): plain frosted fill instead of Liquid Glass, to compare cost.
    static let flat = UserDefaults.standard.bool(forKey: "flatGlass")
}

extension View {
    /// The floating-panel background used by the HUD.
    @ViewBuilder
    func hudGlass<S: Shape>(in shape: S) -> some View {
        if HUDGlass.flat {
            background(Color.white.opacity(0.88), in: shape)
        } else {
            glassEffect(.regular, in: shape)
        }
    }
}
