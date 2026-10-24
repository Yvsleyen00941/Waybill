import RealityKit
import SwiftUI

/// The whole screen: the 3D world fills it, the interface floats on top,
/// and the loading screen plays every time the app opens.
struct GameScreen: View {
    let game: GameModel
    let world: WorldController
    @State private var loader: LoadingScreen.Kind? = UserDefaults.standard.bool(forKey: "skipIntro") ? nil : .launch
    @State private var hudVisible = UserDefaults.standard.bool(forKey: "skipIntro")
    @State private var showExpansion = false
    @State private var showFinale = false
    @State private var curtain: RegionConfig?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            WorldView(world: world)
                .ignoresSafeArea()
            if !UserDefaults.standard.bool(forKey: "hideHUD") { // screenshot mode leaves the interface out
                HUD(world: world, game: game, onExpand: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        if game.region.next == nil { showFinale = true } else { showExpansion = true }
                    }
                })
                    .opacity(hudVisible ? 1 : 0)
                    .scaleEffect(hudVisible ? 1 : 1.03)
            }
            if let report = game.awayReport, hudVisible, loader == nil, !UserDefaults.standard.bool(forKey: "hideHUD") {
                AwayReportCard(report: report, regionName: game.config.name, unit: game.config.unit.many) {
                    withAnimation(.easeInOut(duration: 0.3)) { game.awayReport = nil }
                }
                .transition(.opacity)
            }
            if showExpansion {
                ExpansionCard(game: game, onConfirm: expand, onCancel: {
                    withAnimation(.easeInOut(duration: 0.25)) { showExpansion = false }
                })
                .transition(.opacity)
            }
            if showFinale {
                FinaleCard(game: game) {
                    game.finish()
                    withAnimation(.easeInOut(duration: 0.5)) { showFinale = false }
                }
                .transition(.opacity)
            }
            if let region = curtain {
                RegionCurtain(region: region)
                    .transition(.opacity)
            }
            if let kind = loader {
                LoadingScreen(
                    kind: kind,
                    siteLine: "R\(game.config.number) · \(game.config.site)",
                    running: scenePhase == .active,
                    steps: { loadingSteps(kind) },
                    onCovered: { hudVisible = false },
                    onReveal: {
                        if kind == .launch { world.flyIn() } else { world.settle() }
                        world.sound.play("whoosh", volume: 0.25)
                        withAnimation(.spring(duration: 0.9, bounce: 0.1).delay(0.55)) { hudVisible = true }
                    },
                    onFinished: { loader = nil })
                .transition(.identity)
            }
        }
        .statusBarHidden()
        .onAppear {
            if let id = UserDefaults.standard.string(forKey: "openExpansion"), !id.isEmpty {
                if game.region.next == nil { showFinale = true } else { showExpansion = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                game.pause()
                // Ready the loading screen for the way back (it fades in over the game when you return)
                if loader == nil, !UserDefaults.standard.bool(forKey: "skipIntro") { loader = .resume }
            case .inactive: game.save(now: true)
            case .active:
                if loader != .resume { game.resumeFromBackground() } // otherwise the loading screen catches up
                world.sound.resume()
            @unknown default: break
            }
        }
    }
}

extension GameScreen {
    /// The real work behind the loading screen, with the line it shows for each piece.
    private func loadingSteps(_ kind: LoadingScreen.Kind) -> [LoadingScreen.Step] {
        let site = game.config.site
        switch kind {
        case .launch:
            var steps = [LoadingScreen.Step(label: "Opening \(site)") { await world.warmUp(frames: 30) }]
            if let report = game.awayReport {
                steps.append(LoadingScreen.Step(label: "Caught up on \(Format.duration(report.seconds)) away") {})
            }
            steps.append(LoadingScreen.Step(label: "Starting the engines") {
                let deadline = ContinuousClock.now + .seconds(3)
                while !world.sound.isReady, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(30))
                }
            })
            return steps
        case .resume:
            let away = game.awaySeconds ?? 0
            return [
                LoadingScreen.Step(label: away > 30 ? "Catching up \(Format.duration(away))" : "Back to \(site)") {
                    try? await Task.sleep(for: .milliseconds(120)) // let the line appear before the catch-up runs
                    game.resumeFromBackground()
                },
                LoadingScreen.Step(label: "Warming up the fleet") { await world.warmUp(frames: 12) },
            ]
        }
    }

    /// Curtain down, rebuild the world for the next region behind it, curtain up onto the fly-in.
    private func expand() {
        guard let next = game.region.next else { return }
        withAnimation(.easeInOut(duration: 0.25)) { showExpansion = false }
        withAnimation(.easeInOut(duration: 0.45)) { curtain = next.config }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            game.expand()
            try? await Task.sleep(for: .milliseconds(1700))
            withAnimation(.easeInOut(duration: 0.8)) { curtain = nil }
        }
    }
}

/// Puts the RealityKit view (UIKit) inside SwiftUI.
struct WorldView: UIViewRepresentable {
    let world: WorldController
    func makeUIView(context: Context) -> ARView { world.arView }
    func updateUIView(_ view: ARView, context: Context) {}
}
