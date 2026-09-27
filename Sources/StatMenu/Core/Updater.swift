import AppKit
import CryptoKit
import Foundation
import Observation

/// Checks GitHub Releases for a newer StatMenu, then downloads, verifies and installs it.
///
/// Each release carries `StatMenu.zip` and `StatMenu.zip.sig` (an Ed25519 signature made with the
/// publisher's private key). The app only installs a download whose signature matches the public key
/// in its Info.plist, so a tampered or substituted file is rejected.
@Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing
        case failed(String)
    }

    struct Release: Equatable {
        let version: String
        let notes: String
        let zipURL: URL
        let signatureURL: URL
        let pageURL: URL
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let repository: String?
    @ObservationIgnored private let publicKey: Curve25519.Signing.PublicKey?

    var automaticallyChecks: Bool {
        didSet { defaults.set(automaticallyChecks, forKey: "updatesAutoCheck"); schedule() }
    }
    var automaticallyInstalls: Bool {
        didSet { defaults.set(automaticallyInstalls, forKey: "updatesAutoInstall") }
    }

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var isConfigured: Bool { repository != nil && publicKey != nil }
    var availableRelease: Release? { if case .available(let r) = state { r } else { nil } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        repository = Bundle.main.object(forInfoDictionaryKey: "StatMenuRepository") as? String
        publicKey = (Bundle.main.object(forInfoDictionaryKey: "StatMenuUpdatePublicKey") as? String)
            .flatMap { Data(base64Encoded: $0) }
            .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
        automaticallyChecks = defaults.object(forKey: "updatesAutoCheck") as? Bool ?? true
        automaticallyInstalls = defaults.object(forKey: "updatesAutoInstall") as? Bool ?? false
        lastChecked = defaults.object(forKey: "updatesLastChecked") as? Date
    }

    /// Starts the daily background check (the first one shortly after launch).
    func start() { schedule() }

    private func schedule() {
        timer?.invalidate()
        guard automaticallyChecks, isConfigured else { return }
        let day: TimeInterval = 86_400
        let sinceLast = lastChecked.map { Date().timeIntervalSince($0) } ?? day
        let firstDelay = max(15, day - sinceLast)
        timer = Timer.scheduledTimer(withTimeInterval: firstDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check(userInitiated: false)
                self?.timer = Timer.scheduledTimer(withTimeInterval: day, repeats: true) { _ in
                    MainActor.assumeIsolated { self?.check(userInitiated: false) }
                }
            }
        }
        timer?.tolerance = 60
    }

    // MARK: Checking

    func check(userInitiated: Bool = true) {
        guard isConfigured, let repository else { state = .failed("Updates aren't set up for this build."); return }
        if case .installing = state { return }
        state = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("StatMenu/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.handleCheck(data: data, response: response, error: error, userInitiated: userInitiated) }
            }
        }.resume()
    }

    private func handleCheck(data: Data?, response: URLResponse?, error: Error?, userInitiated: Bool) {
        lastChecked = Date()
        defaults.set(lastChecked, forKey: "updatesLastChecked")
        guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]] else {
            state = .failed(error?.localizedDescription ?? "Couldn't reach GitHub. Try again later.")
            return
        }
        func asset(_ name: String) -> URL? {
            assets.first { $0["name"] as? String == name }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.isNewer(version, than: currentVersion) else { state = .upToDate; return }
        guard let zip = asset("StatMenu.zip"), let sig = asset("StatMenu.zip.sig") else {
            state = .failed("Version \(version) is out, but its download isn't ready yet.")
            return
        }
        let release = Release(version: version, notes: json["body"] as? String ?? "", zipURL: zip, signatureURL: sig, pageURL: page)
        state = .available(release)
        if automaticallyInstalls && !userInitiated { install(release) }
    }

    /// Compares dotted version numbers numerically ("1.10" is newer than "1.9").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Installing

    func install(_ release: Release) {
        guard let publicKey else { return }
        state = .installing
        Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error>
            do {
                let (zipFile, _) = try await URLSession.shared.download(from: release.zipURL)
                let (sigData, _) = try await URLSession.shared.data(from: release.signatureURL)
                let zipData = try Data(contentsOf: zipFile)
                guard let sigText = String(data: sigData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let signature = Data(base64Encoded: sigText),
                      publicKey.isValidSignature(signature, for: zipData) else {
                    throw UpdateError("The download didn't pass the security check, so it wasn't installed.")
                }
                result = .success(try Self.unpack(zipFile))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let newApp): self.replaceAndRelaunch(with: newApp, release: release)
                case .failure(let error): self.state = .failed((error as? UpdateError)?.message ?? error.localizedDescription)
                }
            }
        }
    }

    /// Unzips the verified download into a temporary folder and returns the StatMenu.app inside.
    private static func unpack(_ zip: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StatMenuUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()
        let app = folder.appendingPathComponent("StatMenu.app")
        guard ditto.terminationStatus == 0,
              Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError("The download didn't contain StatMenu.")
        }
        return app
    }

    private func replaceAndRelaunch(with newApp: URL, release: Release) {
        let current = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
        } catch {
            // No permission to replace the installed copy: show the verified new version instead.
            NSWorkspace.shared.activateFileViewerSelecting([newApp])
            state = .failed("Couldn't replace StatMenu automatically. Drag the new version into Applications.")
            return
        }
        // Relaunch the new copy once this one has quit.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", current.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}

private struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
