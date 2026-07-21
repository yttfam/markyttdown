import Foundation
import AppKit

@MainActor
enum UpdateInstaller {
    enum InstallError: Error, LocalizedError {
        case downloadFailed(String)
        case invalidArchive(String)
        case verificationFailed(String)
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let s):    return "Download failed: \(s)"
            case .invalidArchive(let s):    return "Invalid archive: \(s)"
            case .verificationFailed(let s): return "Signature check failed: \(s)"
            case .installFailed(let s):     return "Install failed: \(s)"
            }
        }
    }

    /// Download a signed .zip of markyttdown.app from `url`, verify its
    /// signature, then hand off to a shell script that atomically replaces
    /// the currently running bundle and relaunches. Terminates the current
    /// process on success — the caller should treat a successful return as
    /// meaning "we're about to quit".
    static func downloadAndInstall(from url: URL) async throws {
        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("markyttdown-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        // 1) Download the .zip into `work`
        let zipURL = work.appendingPathComponent("update.zip")
        do {
            let (tmpURL, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw InstallError.downloadFailed("HTTP \(http.statusCode)")
            }
            try FileManager.default.moveItem(at: tmpURL, to: zipURL)
        } catch let err as InstallError {
            throw err
        } catch {
            throw InstallError.downloadFailed(error.localizedDescription)
        }

        // 2) Extract with `ditto` (preserves the app bundle's metadata + the
        //    stapled notarization ticket; `unzip` doesn't).
        let extractDir = work.appendingPathComponent("extract")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", ["-xk", zipURL.path, extractDir.path],
                       throwing: { InstallError.invalidArchive($0) })

        // 3) Find the resulting .app bundle
        let items = (try? FileManager.default.contentsOfDirectory(at: extractDir,
                                                                  includingPropertiesForKeys: nil)) ?? []
        guard let newApp = items.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.invalidArchive("no .app inside archive")
        }

        // 4) Verify the downloaded bundle's Developer ID signature before we
        //    install it over the running one.
        try runProcess("/usr/sbin/spctl", ["--assess", "--type", "execute", newApp.path],
                       throwing: { InstallError.verificationFailed($0) })

        // 5) Write the installer script and launch it detached
        let installedApp = Bundle.main.bundleURL
        let scriptURL = work.appendingPathComponent("install.sh")
        let script = installerScript(
            currentPID: ProcessInfo.processInfo.processIdentifier,
            newAppPath: newApp.path,
            installedAppPath: installedApp.path,
            logPath: work.appendingPathComponent("install.log").path
        )
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: scriptURL.path)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptURL.path]
        do {
            try launcher.run()
        } catch {
            throw InstallError.installFailed(error.localizedDescription)
        }

        // 6) Quit. The script polls for our PID to disappear before swapping
        //    bundles and calling `open` on the fresh app.
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static func runProcess(_ path: String,
                                   _ args: [String],
                                   throwing: (String) -> Error) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe
        do {
            try task.run()
        } catch {
            throw throwing(error.localizedDescription)
        }
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.availableData,
                                encoding: .utf8) ?? ""
            throw throwing("\(path) exited \(task.terminationStatus): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private static func installerScript(currentPID: Int32,
                                        newAppPath: String,
                                        installedAppPath: String,
                                        logPath: String) -> String {
        """
        #!/bin/bash
        exec > "\(logPath)" 2>&1
        set -x
        PID=\(currentPID)
        NEW="\(newAppPath)"
        DEST="\(installedAppPath)"

        # Wait up to 30s for the old app to exit.
        for _ in $(seq 1 300); do
          kill -0 "$PID" 2>/dev/null || break
          sleep 0.1
        done

        # Move the old bundle aside, drop the new one in place, launch it.
        BACKUP="${DEST}.markyttdown-old"
        rm -rf "$BACKUP"
        if [ -e "$DEST" ]; then
          mv "$DEST" "$BACKUP" || { echo "swap failed"; exit 1; }
        fi
        mv "$NEW" "$DEST" || { echo "install failed"; mv "$BACKUP" "$DEST"; exit 1; }

        /usr/bin/open "$DEST"
        rm -rf "$BACKUP"
        """
    }
}
