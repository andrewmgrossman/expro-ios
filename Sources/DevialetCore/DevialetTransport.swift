import Foundation
import Network

public final class DevialetTransport: DevialetTransporting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "DevialetCore.transport")
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []

    public init() {}

    public func startStatusListener(
        onPacket: @escaping @Sendable (Data, String?) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        if listener != nil { return }

        let port = NWEndpoint.Port(rawValue: DevialetProtocol.statusPort)!
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters, on: port)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    onError(error)
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection: connection, onPacket: onPacket, onError: onError)
            }

            self.listener = listener
            listener.start(queue: queue)
        } catch {
            throw AmpControlError.listenerStartupFailed(error.localizedDescription)
        }
    }

    public func stopStatusListener() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.activeConnections.forEach { $0.cancel() }
            self.activeConnections.removeAll()
        }
    }

    public func send(packet: Data, to ipAddress: String) async throws {
        let port = NWEndpoint.Port(rawValue: DevialetProtocol.commandPort)!
        let host = NWEndpoint.Host(ipAddress)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = NWConnection(host: host, port: port, using: .udp)
            let completion = CompletionGate(connection: connection, continuation: continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if let error {
                            completion.finish(.failure(error))
                        } else {
                            completion.finish(.success(()))
                        }
                    })
                case .failed(let error):
                    completion.finish(.failure(error))
                case .cancelled:
                    completion.finish(.failure(AmpControlError.decodeFailed(reason: "UDP command cancelled before send")))
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    private func accept(
        connection: NWConnection,
        onPacket: @escaping @Sendable (Data, String?) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeConnections.append(connection)

            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed(let error):
                    onError(error)
                    connection.cancel()
                    self?.remove(connection)
                case .cancelled:
                    self?.remove(connection)
                default:
                    break
                }
            }

            connection.start(queue: self.queue)
            self.receiveNext(connection: connection, onPacket: onPacket, onError: onError)
        }
    }

    private func receiveNext(
        connection: NWConnection,
        onPacket: @escaping @Sendable (Data, String?) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                onError(error)
                connection.cancel()
                self.remove(connection)
                return
            }

            if let data, !data.isEmpty {
                let sourceIP = Self.host(from: connection.endpoint)
                onPacket(data, sourceIP)
            }

            self.receiveNext(connection: connection, onPacket: onPacket, onError: onError)
        }
    }

    private func remove(_ connection: NWConnection) {
        queue.async { [weak self] in
            self?.activeConnections.removeAll(where: { $0 === connection })
        }
    }

    private static func host(from endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        let raw = host.debugDescription
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }
}

private final class CompletionGate: @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Void, Error>
    private let lock = NSLock()
    private var resolved = false

    init(connection: NWConnection, continuation: CheckedContinuation<Void, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        let shouldResolve = lock.withLock { () -> Bool in
            if resolved { return false }
            resolved = true
            return true
        }

        guard shouldResolve else { return }

        connection.cancel()
        switch result {
        case .success:
            continuation.resume(returning: ())
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
