import Foundation
import Network
import Observation

/// Sends pad input to the Godot receiver (`phone_pad.gd`) over UDP.
///
/// Messages, plain text:
///   `b <button> <1|0>`   a button went down or up (sent the moment it happens)
///   `s <b,b,...>`        the full set of held buttons, every 0.2 s, so a lost
///                        packet can never leave a button stuck down
/// Godot answers each `s` with `ok`, which is how the app knows it is connected.
@Observable
final class PadLink {
    static let port: UInt16 = 9876

    var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: "host")
            reconnect()
        }
    }
    private(set) var connected = false

    private var connection: NWConnection?
    private var held: Set<Int> = []
    private var lastReply = Date.distantPast
    private var timer: Timer?

    init() {
        host = UserDefaults.standard.string(forKey: "host") ?? ""
        reconnect()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.heartbeat() }
        }
    }

    func set(_ control: Control, pressed: Bool) {
        let b = control.godotButton
        if pressed { held.insert(b) } else { held.remove(b) }
        send("b \(b) \(pressed ? 1 : 0)")
    }

    private func heartbeat() {
        send("s " + held.sorted().map(String.init).joined(separator: ","))
        connected = Date().timeIntervalSince(lastReply) < 1.0
    }

    private func reconnect() {
        connection?.cancel()
        connection = nil
        connected = false
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let port = NWEndpoint.Port(rawValue: Self.port) else { return }

        let params = NWParameters.udp
        params.serviceClass = .interactiveVoice // lowest-latency Wi-Fi queue
        let conn = NWConnection(host: NWEndpoint.Host(trimmed), port: port, using: params)
        connection = conn
        conn.start(queue: .main)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            MainActor.assumeIsolated {
                guard let self, self.connection === conn else { return }
                if let data, String(decoding: data, as: UTF8.self) == "ok" {
                    self.lastReply = Date()
                    self.connected = true
                }
                if error == nil { self.receive(on: conn) }
            }
        }
    }

    private func send(_ message: String) {
        connection?.send(content: Data(message.utf8), completion: .idempotent)
    }
}
