import Foundation

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct ProxyReply: Sendable {
    public var status: Int
    public var health: ProxyHealth?
    public var error: String?
    public init(status: Int, health: ProxyHealth? = nil, error: String? = nil) {
        self.status = status; self.health = health; self.error = error
    }
}

public struct ProxyCommand: Codable, Sendable {
    public var transactionID: String
    public var epoch: Int
    public var bootID: String
    public var runtimeID: String
    public var configRevision: String
    public var lease: String?
    public var generation: Int?
    enum CodingKeys: String, CodingKey {
        case epoch, lease, generation
        case transactionID = "transaction_id", bootID = "boot_id", runtimeID = "runtime_id", configRevision = "config_revision"
    }
    public init(journal: UpdateJournal, health: ProxyHealth, lease: String? = nil, generation: Int? = nil) throws {
        guard let runtimeID = health.runtimeID, let revision = health.configRevision else { throw UpdateFailure.identityMismatch }
        self.transactionID = journal.transactionID; self.epoch = journal.epoch
        self.bootID = health.bootID; self.runtimeID = runtimeID; self.configRevision = revision
        self.lease = lease; self.generation = generation
    }
}

public struct ProxyClient: Sendable {
    public typealias Exchange = @Sendable (String, ProxyCommand?) async throws -> ProxyReply
    public let exchange: Exchange

    public init(exchange: @escaping Exchange) { self.exchange = exchange }

    public init(configPath: URL) throws {
        struct Configuration: Decodable { var port: Int; var listen_host: String? }
        let config = try Disk.decode(Configuration.self, at: configPath)
        guard (1...65535).contains(config.port), config.listen_host == nil || config.listen_host == "127.0.0.1" else {
            throw UpdateFailure.invalidPath
        }
        let tokenPath = URL(fileURLWithPath: configPath.path + ".control-token")
        let origin = "http://127.0.0.1:\(config.port)/_proxy/update/v1/"
        self.exchange = { action, command in
            guard ["health", "prepare-if-idle", "renew-lease", "abort-prepare", "commit-stop", "activate"].contains(action) else {
                throw UpdateFailure.invalidCommand
            }
            let token = String(decoding: try Disk.read(tokenPath, limit: 64), as: UTF8.self)
            guard Disk.isDigest(token), let url = URL(string: origin + action) else { throw UpdateFailure.identityMismatch }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 3
            configuration.timeoutIntervalForResource = 5
            let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: url)
            request.httpMethod = command == nil ? "GET" : "POST"
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            if let command {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(command)
            }
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.url?.host == "127.0.0.1", response.url?.port == config.port else {
                throw UpdateFailure.proxyUnreachable
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 262_144 else { throw UpdateFailure.proxyUnreachable }
                data.append(byte)
            }
            let health = try? JSONDecoder().decode(ProxyHealth.self, from: data)
            struct Failure: Decodable { var error: String }
            return ProxyReply(status: response.statusCode, health: health,
                              error: (try? JSONDecoder().decode(Failure.self, from: data))?.error)
        }
    }

    public func health() async throws -> ProxyHealth {
        let reply = try await exchange("health", nil)
        guard reply.status == 200, let health = reply.health, health.updateProtocol == 1,
              health.managed, health.payloadVerified, UUID(uuidString: health.bootID) != nil,
              health.workTotal >= 0, health.work.values.allSatisfy({ $0 >= 0 }),
              health.workTotal == health.work.values.reduce(0, +) else { throw UpdateFailure.identityMismatch }
        return health
    }
}
