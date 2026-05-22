// UDPClient.swift
// Handles all UDP networking for OBTrack.
// Opens a UDP socket using Network.framework and sends JSON packets
// to the user-configured destination IP and port.
// Designed to be non-crashing — unreachable destinations are silently ignored.

import Foundation
import Network

// MARK: - UDPClient

final class UDPClient {

    // MARK: - Properties

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.obtrack.udp", qos: .userInteractive)

    /// Human-readable status of the last send operation.
    /// Only mutated from `queue`. Do NOT read this directly across threads —
    /// observe changes via `onStatusChange` instead.
    private(set) var sendStatus: String = "Idle"

    /// Invoked on `queue` every time `sendStatus` changes. Marshal to the
    /// main thread inside the closure if you bind the value to UI state.
    var onStatusChange: ((String) -> Void)?

    private func update(status: String) {
        sendStatus = status
        onStatusChange?(status)
    }

    // MARK: - Public API

    /// Configure a new UDP connection to the given host and port.
    /// Call this before sending any packets, and again whenever the destination changes.
    func configure(host: String, port: UInt16) {
        // Tear down any existing connection first
        connection?.cancel()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            queue.async { [weak self] in self?.update(status: "Invalid port") }
            return
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )

        // Create a UDP connection with no TLS
        connection = NWConnection(to: endpoint, using: .udp)
        connection?.stateUpdateHandler = { [weak self] state in
            // stateUpdateHandler is invoked on `queue` (set via .start(queue:))
            switch state {
            case .ready:
                self?.update(status: "UDP ready")
            case .failed(let error):
                // Do not crash — log the error and reset
                self?.update(status: "UDP error: \(error.localizedDescription)")
                self?.connection?.cancel()
            case .cancelled:
                self?.update(status: "UDP cancelled")
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    /// Send raw Data over the configured UDP connection.
    /// Silently drops the packet if the connection is not ready.
    func send(_ data: Data) {
        guard let connection = connection else { return }

        connection.send(content: data, completion: .contentProcessed({ [weak self] error in
            // Completion runs on `queue` (the connection's queue).
            if let error = error {
                // Do not crash — UDP delivery is best-effort
                self?.update(status: "Send error: \(error.localizedDescription)")
            } else {
                self?.update(status: "Sent \(data.count) bytes")
            }
        }))
    }

    /// Close the UDP connection cleanly.
    func close() {
        connection?.cancel()
        connection = nil
        queue.async { [weak self] in self?.update(status: "Disconnected") }
    }
}
