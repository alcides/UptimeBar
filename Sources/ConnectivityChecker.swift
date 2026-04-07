import Foundation
import Network

enum ServerStatus {
    case online
    case offline
    case checking
    case unknown
}

struct ServerEntry: Equatable {
    let host: String
    let port: UInt16

    var displayName: String {
        "\(host):\(port)"
    }
}

final class ConnectivityChecker {
    private let queue = DispatchQueue(label: "com.uptimebar.checker", attributes: .concurrent)
    private let timeout: TimeInterval = 5

    func checkInternet(completion: @escaping (Bool) -> Void) {
        let hosts: [(String, UInt16)] = [("google.com", 443), ("sapo.pt", 443)]
        let group = DispatchGroup()
        var anyReachable = false
        var connections: [NWConnection] = []

        for (host, port) in hosts {
            group.enter()
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            connections.append(connection)

            var completed = false
            let lock = NSLock()

            connection.stateUpdateHandler = { state in
                lock.lock()
                guard !completed else { lock.unlock(); return }
                switch state {
                case .ready:
                    completed = true
                    lock.unlock()
                    anyReachable = true
                    connection.cancel()
                    group.leave()
                case .failed, .cancelled:
                    completed = true
                    lock.unlock()
                    group.leave()
                default:
                    lock.unlock()
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                lock.lock()
                guard !completed else { lock.unlock(); return }
                completed = true
                lock.unlock()
                connection.cancel()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(anyReachable)
        }
    }

    func checkServer(_ server: ServerEntry, completion: @escaping (ServerStatus) -> Void) {
        let connection = NWConnection(
            host: NWEndpoint.Host(server.host),
            port: NWEndpoint.Port(rawValue: server.port)!,
            using: .tcp
        )

        var completed = false
        let lock = NSLock()

        connection.stateUpdateHandler = { state in
            lock.lock()
            guard !completed else { lock.unlock(); return }
            switch state {
            case .ready:
                completed = true
                lock.unlock()
                connection.cancel()
                DispatchQueue.main.async { completion(.online) }
            case .failed:
                completed = true
                lock.unlock()
                connection.cancel()
                DispatchQueue.main.async { completion(.offline) }
            default:
                lock.unlock()
            }
        }

        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + timeout) {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            completed = true
            lock.unlock()
            connection.cancel()
            DispatchQueue.main.async { completion(.offline) }
        }
    }

    func checkAll(servers: [ServerEntry], completion: @escaping (Bool, [ServerEntry: ServerStatus]) -> Void) {
        checkInternet { [weak self] online in
            guard let self, online else {
                var results: [ServerEntry: ServerStatus] = [:]
                for server in servers { results[server] = .unknown }
                completion(false, results)
                return
            }

            let group = DispatchGroup()
            var results: [ServerEntry: ServerStatus] = [:]
            let lock = NSLock()

            for server in servers {
                group.enter()
                self.checkServer(server) { status in
                    lock.lock()
                    results[server] = status
                    lock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(true, results)
            }
        }
    }
}

extension ServerEntry: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(host)
        hasher.combine(port)
    }
}
