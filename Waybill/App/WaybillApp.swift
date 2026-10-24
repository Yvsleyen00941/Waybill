import SwiftUI

/// The entry point of the app. iPadOS starts here and shows `GameScreen`.
///
/// The game and the 3D world are created exactly once, here. (Creating them inside a view's `init`
/// would build a new world every time SwiftUI refreshes the screen.)
@main
struct WaybillApp: App {
    @State private var game: GameModel
    @State private var world: WorldController

    init() {
        let game = GameModel()
        _game = State(initialValue: game)
        _world = State(initialValue: WorldController(game: game))
    }

    var body: some Scene {
        WindowGroup {
            GameScreen(game: game, world: world)
                .persistentSystemOverlays(.hidden)
                .preferredColorScheme(.light) // the interface is designed light; Dark Mode would turn the glass grey
        }
    }
}
