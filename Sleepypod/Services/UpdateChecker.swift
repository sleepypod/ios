import Foundation
import Observation

@MainActor
@Observable
final class UpdateChecker {
    var latestVersion: String?
    var latestReleaseNotes: String?
    var isChecking = false
    var lastChecked: Date?

    private let repoOwner = "sleepypod"
    private let repoName = "core"

    /// The version running on the pod (from device status API)
    var runningVersion: String?

    /// The branch running on the pod
    var runningBranch: String?

    /// The branch to check for updates (user-selected)
    var trackingBranch: String = UserDefaults.standard.string(forKey: "podBranch") ?? "main"

    /// Latest commit SHA on the tracking branch (for non-main branches)
    var latestCommitSHA: String?

    var updateAvailable: Bool {
        guard let latest = latestVersion, let running = runningVersion else { return false }
        return compareVersions(latest, isNewerThan: running)
    }

    func checkForUpdate() async {
        isChecking = true
        defer {
            isChecking = false
            lastChecked = Date()
        }

        if trackingBranch == "main" {
            await checkRelease()
        } else {
            await checkBranch()
        }
    }

    private func checkRelease() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
            latestReleaseNotes = release.body
            latestCommitSHA = nil
        } catch {
            // Silently fail
        }
    }

    private func checkBranch() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/branches/\(trackingBranch)") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let branch = try JSONDecoder().decode(GitHubBranch.self, from: data)
            latestCommitSHA = String(branch.commit.sha.prefix(7))
            latestVersion = nil
            latestReleaseNotes = branch.commit.commit.message
        } catch {
            // Silently fail
        }
    }

    private func compareVersions(_ latest: String, isNewerThan running: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let runningParts = running.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(latestParts.count, runningParts.count) {
            let l = i < latestParts.count ? latestParts[i] : 0
            let r = i < runningParts.count ? runningParts[i] : 0
            if l > r { return true }
            if l < r { return false }
        }
        return false
    }
}

private struct GitHubBranch: Decodable {
    let name: String
    let commit: GitHubBranchCommit
}

private struct GitHubBranchCommit: Decodable {
    let sha: String
    let commit: GitHubCommitDetail
}

private struct GitHubCommitDetail: Decodable {
    let message: String
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
    }
}
