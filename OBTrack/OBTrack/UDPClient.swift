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

    /// Human-readable status of the last send operation
    @Published var sendStatus: String = "Idle"

    // MARK: - Public API

    /// Configure a new UDP connection to the given host and port.
    /// Call this before sending any packets, and again whenever the destination changes.
    func configure(host: String, port: UInt16) {
        // Tear down any existing connection first
        connection?.cancel()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            sendStatus = "Invalid port"
            return
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )

        // Create a UDP connection with no TLS
        connection = NWConnection(to: endpoint, using: .udp)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendStatus = "UDP ready"
            case .failed(let error):
                // Do not crash — log the error and reset
                self?.sendStatus = "UDP error: \(error.localizedDescription)"
                self?.connection?.cancel()
            case .cancelled:
                self?.sendStatus = "UDP cancelled"
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
            if let error = error {
                // Do not crash — UDP delivery is best-effort
                self?.sendStatus = "Send error: \(error.localizedDescription)"
            } else {
                self?.sendStatus = "Sent \(data.count) bytes"
            }
        }))
    }

    /// Close the UDP connection cleanly.
    func close() {
        connection?.cancel()
        connection = nil
        sendStatus = "Disconnected"
    }
}
