import Foundation
import AppKit

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repo = "yttfam/markyttdown"

    private let session = URLSession.shared
    private let lastCheckKey = "lastUpdateCheck"
    private let skippedTagKey = "skippedUpdateTag"
    private let throttle: TimeInterval = 86_400 // 24h

    struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    func checkSilentlyIfDue() async {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - last < throttle { return }
        UserDefaults.standard.set(now, forKey: lastCheckKey)

        guard let r = try? await fetchLatest() else { return }
        guard isNewer(r.tag_name) else { return }
        if UserDefaults.standard.string(forKey: skippedTagKey) == r.tag_name { return }
        present(release: r)
    }

    func checkManually() async {
        do {
            let r = try await fetchLatest()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            if isNewer(r.tag_name) {
                present(release: r)
            } else {
                presentUpToDate()
            }
        } catch {
            presentError(error)
        }
    }

    private func fetchLatest() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("markyttdown", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: - Versioning

    private func currentVersion() -> (marketing: String, build: Int) {
        let info = Bundle.main.infoDictionary ?? [:]
        let m = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let b = Int(info["CFBundleVersion"] as? String ?? "0") ?? 0
        return (m, b)
    }

    private func parseTag(_ tag: String) -> (marketing: String, build: Int)? {
        let s = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        guard let m = parts.first.map(String.init), !m.isEmpty else { return nil }
        // Reject anything that isn't dot-separated numbers (e.g. "garbage").
        let comps = m.split(separator: ".")
        guard !comps.isEmpty, comps.allSatisfy({ Int($0) != nil }) else { return nil }
        let b = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return (m, b)
    }

    func isNewer(_ tag: String) -> Bool {
        guard let remote = parseTag(tag) else { return false }
        let local = currentVersion()
        let ac = remote.marketing.compare(local.marketing, options: .numeric)
        if ac != .orderedSame { return ac == .orderedDescending }
        return remote.build > local.build
    }

    // MARK: - UI

    private func present(release: Release) {
        let alert = NSAlert()
        let cur = currentVersion()
        alert.messageText = "markyttdown \(release.tag_name) is available"
        alert.informativeText = "You're on \(cur.marketing) (build \(cur.build))."
        // Prefer the in-app installer when the release ships a .zip; otherwise
        // fall back to opening the download page in the browser.
        let zip = release.assets.first { $0.name.hasSuffix(".zip") }
        let installButtonTitle = zip != nil ? "Install & Restart" : "Download"
        alert.addButton(withTitle: installButtonTitle)
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let zip, let url = URL(string: zip.browser_download_url) {
                Task { await downloadAndInstall(from: url) }
            } else {
                let dmg = release.assets.first { $0.name.hasSuffix(".dmg") }
                let target = URL(string: dmg?.browser_download_url ?? release.html_url)
                    ?? URL(string: release.html_url)
                if let target { NSWorkspace.shared.open(target) }
            }
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(release.tag_name, forKey: skippedTagKey)
        default:
            break
        }
    }

    private func downloadAndInstall(from url: URL) async {
        do {
            try await UpdateInstaller.downloadAndInstall(from: url)
            // On success the installer script quits us — this line is
            // reached only if something went wrong after that point.
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't install the update"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func presentUpToDate() {
        let cur = currentVersion()
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "markyttdown \(cur.marketing) (build \(cur.build))."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
