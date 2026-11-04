import SwiftUI

struct ContentView: View {
    @State private var link = PadLink()
    @State private var draftHost = ""
    @FocusState private var editingHost: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .top) {
            PadSurface(link: link, releaseAll: scenePhase != .active)
                .ignoresSafeArea()

            hostBar
                .padding(.top, 12)
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .onAppear { draftHost = link.host }
    }

    /// Small pill at the top: connection light + the Mac's IP address.
    private var hostBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(link.connected ? Color.green : (link.host.isEmpty ? Color.gray : Color.orange))
                .frame(width: 9, height: 9)
            TextField("Mac IP shown in Godot output", text: $draftHost)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($editingHost)
                .submitLabel(.done)
                .onSubmit { link.host = draftHost }
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 190)
            Text(link.connected ? "connected" : (link.host.isEmpty ? "set IP" : "waiting"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

/// Bridges the UIKit multi-touch pad into SwiftUI.
struct PadSurface: UIViewRepresentable {
    let link: PadLink
    let releaseAll: Bool

    func makeUIView(context: Context) -> PadView {
        let view = PadView()
        view.onChange = { control, pressed in link.set(control, pressed: pressed) }
        return view
    }

    func updateUIView(_ view: PadView, context: Context) {
        if releaseAll { view.releaseAll() }
    }
}
