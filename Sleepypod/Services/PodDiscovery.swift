import Foundation
import Network
import Observation

@MainActor
@Observable
final class PodDiscovery {
    var discoveredPods: [DiscoveredPod] = []
    var isSearching = false

    private var browser: NWBrowser?

    struct DiscoveredPod: Identifiable, Sendable {
        let id: String
        let name: String
        let host: String
        let port: UInt16
    }

    func startBrowsing() {
        stopBrowsing()
        isSearching = true
        discoveredPods = []

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sleepypod._tcp", domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
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

        // Auto-stop after 15 seconds to save battery
        Task {
            try? await Task.sleep(for: .seconds(15))
            if self.isSearching {
                self.stopBrowsing()
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

            let pod = DiscoveredPod(
                id: "\(name).\(type).\(domain)",
                name: name,
                host: name,
                port: 3000
            )
            pods.append(pod)
        }

        discoveredPods = pods
    }

    /// Resolve a discovered pod's endpoint to get the actual IP address
    func resolve(_ pod: DiscoveredPod) async -> String? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.service(
                name: pod.name,
                type: "_sleepypod._tcp",
                domain: "local.",
                interface: nil
            )
            let params = NWParameters.tcp
            let connection = NWConnection(to: endpoint, using: params)

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
                            hostString = "\(addr)"
                        case .name(let name, _):
                            hostString = name
                        @unknown default:
                            hostString = "\(host)"
                        }
                        connection.cancel()
                        continuation.resume(returning: hostString)
                    } else {
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                case .failed, .cancelled:
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }

            connection.start(queue: .main)

            // Timeout after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if connection.state != .ready {
                    connection.cancel()
                }
            }
        }
    }
}

