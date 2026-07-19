#if DEBUG
import SwiftUI

/// Launch-only preview used by automated Simulator screenshots. This stays
/// separate from the interactive gallery so the selected clip fills the root.
struct MascotPreviewView: View {
    let state: MascotState
    @State private var oneShotTrigger = 0

    private var isOneShot: Bool {
        state == .celebrate || state == .surprised
    }

    private var replayDelay: Duration {
        state == .celebrate ? .milliseconds(1_800) : .milliseconds(900)
    }

    var body: some View {
        ZStack {
            Color(red: 0.88, green: 0.95, blue: 0.98)
                .ignoresSafeArea()

            LottieMascotView(
                state: isOneShot ? .idle : state,
                oneShotState: isOneShot ? state : nil,
                oneShotTrigger: oneShotTrigger
            )
            .frame(maxWidth: 420, maxHeight: 420)
            .padding(24)
        }
        .task(id: state) {
            guard isOneShot else { return }

            oneShotTrigger += 1
            while !Task.isCancelled {
                try? await Task.sleep(for: replayDelay)
                guard !Task.isCancelled else { return }
                oneShotTrigger += 1
            }
        }
    }
}

/// Debug-only clip switcher for verifying the strawberry prototype without
/// entering the NFC or BLE focus flows.
struct MascotGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTokens) private var design
    @State private var baseState: MascotState = .idle
    @State private var oneShotState: MascotState?
    @State private var oneShotTrigger = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: design.spacing(24)) {
                LottieMascotView(
                    state: baseState,
                    oneShotState: oneShotState,
                    oneShotTrigger: oneShotTrigger
                )
                .frame(width: design.hero(260), height: design.hero(260))
                .background(
                    design.surface.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: design.radius(24))
                )

                Picker("Base state", selection: $baseState) {
                    Text("Idle").tag(MascotState.idle)
                    Text("On duty").tag(MascotState.onDuty)
                    Text("Blocking").tag(MascotState.blocking)
                }
                .pickerStyle(.segmented)

                HStack(spacing: design.spacing(12)) {
                    oneShotButton("Celebrate", state: .celebrate, icon: "sparkles")
                    oneShotButton("Surprised", state: .surprised, icon: "exclamationmark.bubble.fill")
                }

                Spacer()
            }
            .padding(design.spacing(22))
            .background(PlayfulBackdrop(tokens: design))
            .navigationTitle("Mascot Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func oneShotButton(
        _ title: String,
        state: MascotState,
        icon: String
    ) -> some View {
        Button {
            oneShotState = state
            oneShotTrigger += 1
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryCTAStyle(tokens: design, isEnabled: true, lockState: false))
    }
}
#endif
