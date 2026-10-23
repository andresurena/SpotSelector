import SwiftUI
import QualityCore

struct SpotSelectorApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: state.isSwitching ? "arrow.triangle.2.circlepath" : "waveform")
            if state.showLabel, let current = state.current {
                Text(current.shortLabel)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let status = state.status {
            Text(status)
            Divider()
        } else if let problem = state.problem {
            Text(problem)
            Button("Try Again") { state.refresh() }
            Divider()
        }

        Section("Spotify Streaming Quality") {
            ForEach(state.menuQualities) { quality in
                Toggle(isOn: Binding(
                    get: { state.current == quality },
                    set: { if $0 { state.select(quality) } }
                )) {
                    Text("\(quality.title) — \(quality.detail)")
                }
                .disabled(state.isSwitching || state.current == nil)
            }
        }

        Divider()

        Menu("Options") {
            Section("Show in Menu") {
                ForEach(Quality.allCases.reversed()) { quality in
                    Toggle(quality.title, isOn: Binding(
                        get: { !state.hidden.contains(quality) },
                        set: { state.setHidden(quality, !$0) }
                    ))
                }
            }
            Divider()
            Toggle("Resume Playback After Switching", isOn: $state.resumePlayback)
            Toggle("Show Quality in Menu Bar", isOn: $state.showLabel)
            Toggle("Launch at Login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
        }

        Divider()

        Button("Quit SpotSelector") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
