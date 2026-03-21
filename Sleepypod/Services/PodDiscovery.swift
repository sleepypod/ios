import Foundation
import Network
import Observation

@MainActor
@Observable
final class PodDiscovery {
    var discoveredPods: [DiscoveredPod] = []
    var isSearching = false
    var status: DiscoveryStatus = .idle
    var connectedPodName: String?

    enum DiscoveryStatus: Equatable {
        case idle
        case scanning
        case found(String)        // device name
        case resolving(String)    // device name
        case connected(String)    // IP
        case failed
    }

    private var browser: NWBrowser?
    private var autoConnecting = false

    struct DiscoveredPod: Identifiable, Sendable {
        let id: String
        let name: String
        let host: String
        let port: UInt16
    }

    // MARK: - Browse

    func startBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = true
        status = .scanning
        discoveredPods = []

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sleepypod._tcp", domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isSearching = true
                case .failed, .cancelled:
                    self.isSearching = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleResults(results)
            }
        }

        browser.start(queue: .main)
        self.browser = browser

        // Auto-stop after 15 seconds
        Task {
            try? await Task.sleep(for: .seconds(15))
            if self.isSearching {
                self.browser?.cancel()
                self.browser = nil
                self.isSearching = false
                // Only set failed if we're still scanning (haven't moved forward)
                if self.status == .scanning {
                    self.status = .failed
                }
            }
        }
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var pods: [DiscoveredPod] = []

        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint else { continue }
            pods.append(DiscoveredPod(
                id: "\(name).\(type).\(domain)",
                name: name,
                host: name,
                port: 3000
            ))
        }

        discoveredPods = pods

        // Only advance status if we're still scanning (don't regress from later states)
        if let first = pods.first, status == .scanning {
            Log.discovery.info("Found device: \(first.name)")
            Haptics.light()
            status = .found(first.name)
        }
    }

    // MARK: - Auto Connect

    func autoConnect(settingsManager: SettingsManager, deviceManager: DeviceManager) async -> String? {
        guard !autoConnecting else { return nil }
        autoConnecting = true
        defer { autoConnecting = false }

        startBrowsing()

        // Wait up to 10 seconds for a device to appear
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if let pod = discoveredPods.first {
                stopBrowsing()
                status = .resolving(pod.name)
                if let ip = await resolve(pod) {
                    Log.discovery.info("Resolved \(pod.name) → \(ip)")
                    Haptics.medium()
                    status = .connected(ip)
                    connectedPodName = pod.name
                    settingsManager.podIP = ip
                    deviceManager.retryConnection()
                    return ip
                } else {
                    Log.discovery.error("Failed to resolve \(pod.name)")
                    Haptics.heavy()
                    status = .failed
                }
                return nil
            }
        }
        Log.discovery.warning("No devices found after 10s scan")
        stopBrowsing()
        if status == .scanning { status = .failed }
        return nil
    }

    // MARK: - Resolve

    func resolve(_ pod: DiscoveredPod) async -> String? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.service(
                name: pod.name,
                type: "_sleepypod._tcp",
                domain: "local.",
                interface: nil
            )
            let params = NWParameters.tcp
            // Prefer IPv4 — some networks have flaky IPv6 that stalls resolution
            params.requiredInterfaceType = .wifi
            if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let connection = NWConnection(to: endpoint, using: params)
            let once = OnceFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let path = connection.currentPath,
                       let endpoint = path.remoteEndpoint,
                       case .hostPort(let host, _) = endpoint {
                        let hostString: String
                        switch host {
                        case .ipv4(let addr):
                            hostString = "\(addr)"
                        case .ipv6(let addr):
                            // Strip zone ID (%en0) and convert IPv4-mapped IPv6 to plain IPv4
                            var raw = "\(addr)"
                            // Remove zone ID (e.g., "%en0", "%%en0")
                            if let pct = raw.firstIndex(of: "%") {
                                raw = String(raw[raw.startIndex..<pct])
                            }
                            // Convert ::ffff:192.168.1.88 → 192.168.1.88
                            if raw.hasPrefix("::ffff:") {
                                raw = String(raw.dropFirst(7))
                            }
                            hostString = raw
                        case .name(let name, _):
                            // Got hostname (e.g. "eight-pod.local") — resolve to IPv4
                            hostString = resolveHostnameToIPv4(name) ?? name
                        @unknown default:
                            hostString = "\(host)"
                        }
                        if once.fire() {
                            connection.cancel()
                            continuation.resume(returning: hostString)
                        }
                    } else {
                        if once.fire() {
                            connection.cancel()
                            continuation.resume(returning: nil)
                        }
                    }
                case .failed, .cancelled:
                    if once.fire() {
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .main)

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if once.fire() {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

}

/// Resolve a hostname (e.g. "eight-pod.local") to an IPv4 address string.
private func resolveHostnameToIPv4(_ hostname: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET // IPv4 only
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, nil, &hints, &result)
        defer { if result != nil { freeaddrinfo(result) } }

        guard status == 0, let info = result else { return nil }

        var addr = info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buf)
}

/// Thread-safe single-fire flag for continuation safety.
private final class OnceFlag: @unchecked Sendable {
    private var _fired = false
    private let lock = NSLock()

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _fired { return false }
        _fired = true
        return true
    }
}
