import AppKit

struct ReleaseInfo {
    let version: String
    let notes: String
    let assetURL: URL
}

enum UpdateError: LocalizedError {
    case http(Int, String)
    case noAsset
    case unsafe(String)
    case install(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): "GitHub a répondu \(code) : \(msg)"
        case .noAsset: "La dernière version ne contient pas AutoCorrection.dmg."
        case .unsafe(let why): "Mise à jour refusée : \(why)"
        case .install(let why): "Installation impossible : \(why)"
        }
    }
}

/// Mise à jour à la demande depuis les Releases publiques du dépôt GitHub.
enum Updater {
    static let repo = "mdany75/AutoCorrection"
    static let assetName = "AutoCorrection.dmg"
    /// Équipe Apple qui signe les versions publiées : seule une app signée par elle est installée.
    static let teamID = "2F5M9B25A6"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Vérification

    /// La dernière version publiée si elle est plus récente que celle qui tourne, sinon nil.
    static func checkForUpdate() async throws -> ReleaseInfo? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.timeoutInterval = 30
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200, let json else {
            throw UpdateError.http(status, (json?["message"] as? String) ?? "réponse inattendue")
        }
        let tag = (json["tag_name"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard !tag.isEmpty,
              let asset = assets.first(where: { $0["name"] as? String == assetName }),
              let urlString = asset["browser_download_url"] as? String, let url = URL(string: urlString)
        else { throw UpdateError.noAsset }
        guard isNewer(tag, than: currentVersion) else { return nil }
        return ReleaseInfo(version: tag, notes: json["body"] as? String ?? "", assetURL: url)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: - Installation

    /// Télécharge l'image disque, vérifie l'app qu'elle contient, puis la substitue à l'actuelle après
    /// la fermeture de celle-ci et la relance. `step` annonce l'étape en cours.
    @MainActor
    static func install(_ release: ReleaseInfo, step: (String) -> Void) async throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoCorrection-update-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            step("Téléchargement de la mise à jour…")
            let (tmp, resp) = try await URLSession.shared.download(from: release.assetURL)
            let dmg = work.appendingPathComponent(assetName)
            try FileManager.default.moveItem(at: tmp, to: dmg)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateError.http(status, "téléchargement refusé") }

            step("Vérification et installation…")
            let staged = try await extractAndVerify(dmg: dmg, in: work, expected: release.version)

            let target = Bundle.main.bundleURL
            guard target.pathExtension == "app",
                  FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
            else { throw UpdateError.install("impossible d'écrire dans \(target.deletingLastPathComponent().path)") }

            let script = work.appendingPathComponent("remplacer.sh")
            try swapScript.write(to: script, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                           target.path, staged.path, work.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    private static let swapScript = """
    #!/bin/bash
    # $1 pid de l'app, $2 app installée, $3 nouvelle app, $4 dossier de travail
    while kill -0 "$1" 2>/dev/null; do sleep 0.3; done
    rm -rf "$2" && ditto "$3" "$2" && open "$2"
    rm -rf "$4"
    """

    private static func extractAndVerify(dmg: URL, in work: URL, expected: String) async throws -> URL {
        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify",
                                           "-mountpoint", mount.path, dmg.path])
        let staged = work.appendingPathComponent("AutoCorrection.app")
        do {
            try await run("/usr/bin/ditto", [mount.appendingPathComponent("AutoCorrection.app").path, staged.path])
        } catch {
            _ = try? await run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            throw error
        }
        _ = try? await run("/usr/bin/hdiutil", ["detach", "-force", mount.path])

        do {
            try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
            let info = try await run("/usr/bin/codesign", ["-dv", "--verbose=2", staged.path])
            guard info.contains("TeamIdentifier=\(teamID)") else {
                throw UpdateError.unsafe("l'application n'est pas signée par le bon développeur")
            }
            try await run("/usr/sbin/spctl", ["-a", "-t", "exec", staged.path])
        } catch let e as UpdateError {
            throw e
        } catch {
            throw UpdateError.unsafe("signature invalide (\(error.localizedDescription))")
        }
        let plist = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleShortVersionString"] as? String == expected else {
            throw UpdateError.unsafe("le numéro de version ne correspond pas à la Release")
        }
        return staged
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.terminationHandler = { proc in
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    cont.resume(returning: out)
                } else {
                    cont.resume(throwing: UpdateError.install("\(URL(fileURLWithPath: path).lastPathComponent) : \(out.trimmingCharacters(in: .whitespacesAndNewlines))"))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}
