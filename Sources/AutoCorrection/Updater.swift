import AppKit

struct ReleaseInfo: Equatable {
    let version: String
    let notes: String
    let assetURL: URL
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case downloading
    case installing
    case error(String)
}

enum UpdateError: LocalizedError {
    case noToken
    case http(Int, String)
    case noAsset
    case unsafe(String)
    case install(String)

    var errorDescription: String? {
        switch self {
        case .noToken: "Ajoutez un jeton GitHub dans les réglages pour vérifier les mises à jour."
        case .http(401, _): "Jeton GitHub refusé : il est invalide ou expiré."
        case .http(404, _): "Dépôt introuvable : le jeton doit avoir la lecture du contenu de mdany75/AutoCorrection."
        case .http(let code, let msg): "GitHub a répondu \(code) : \(msg)"
        case .noAsset: "La version publiée ne contient pas AutoCorrection.dmg."
        case .unsafe(let why): "Mise à jour refusée : \(why)"
        case .install(let why): "Installation impossible : \(why)"
        }
    }
}

/// Retire l'en-tête Authorization quand GitHub redirige vers un autre serveur (le stockage des fichiers).
private final class DropAuthOnRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var r = request
        if r.url?.host != task.originalRequest?.url?.host { r.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(r)
    }
}

/// Mises à jour par les Releases GitHub du dépôt (privé : jeton en lecture seule dans le Trousseau).
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repo = "mdany75/AutoCorrection"
    static let assetName = "AutoCorrection.dmg"
    static let teamID = "2F5M9B25A6"

    @Published private(set) var state: UpdateState = .idle { didSet { onState?(state) } }
    var onState: ((UpdateState) -> Void)?
    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    // MARK: - Vérification

    /// Vérifie au lancement, puis toutes les heures si la dernière vérification date de plus de 20 h.
    func startAutoChecks() {
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.autoCheck() }
        }
        Task { try? await Task.sleep(for: .seconds(5)); await autoCheck() }
    }

    private func autoCheck() async {
        guard Prefs.autoCheckUpdates, !isBusy, Keychain.read(.github)?.isEmpty == false else { return }
        let last = UserDefaults.standard.object(forKey: Prefs.lastUpdateCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 3600 else { return }
        await check()
    }

    func check() async {
        guard !isBusy else { return }
        state = .checking
        do {
            let release = try await fetchLatest()
            UserDefaults.standard.set(Date(), forKey: Prefs.lastUpdateCheckKey)
            state = Self.isNewer(release.version, than: Self.currentVersion) ? .available(release) : .upToDate
        } catch {
            state = .error(error.localizedDescription)
        }
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

    private func request(_ path: String, accept: String) throws -> URLRequest {
        guard let token = Keychain.read(.github), !token.isEmpty else { throw UpdateError.noToken }
        var req = URLRequest(url: URL(string: path)!)
        req.timeoutInterval = 30
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return req
    }

    private func fetchLatest() async throws -> ReleaseInfo {
        let req = try request("https://api.github.com/repos/\(Self.repo)/releases/latest",
                              accept: "application/vnd.github+json")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200, let json else {
            throw UpdateError.http(status, (json?["message"] as? String) ?? "réponse inattendue")
        }
        let tag = (json["tag_name"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard !tag.isEmpty,
              let asset = assets.first(where: { $0["name"] as? String == Self.assetName }),
              let urlString = asset["url"] as? String, let url = URL(string: urlString)
        else { throw UpdateError.noAsset }
        return ReleaseInfo(version: tag, notes: json["body"] as? String ?? "", assetURL: url)
    }

    // MARK: - Installation

    /// Télécharge l'image disque, vérifie l'application qu'elle contient, puis la substitue à l'actuelle
    /// après la fermeture de celle-ci et la relance.
    func install() async {
        guard case .available(let release) = state else { return }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoCorrection-update-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            state = .downloading
            let req = try request(release.assetURL.absoluteString, accept: "application/octet-stream")
            let (tmp, resp) = try await URLSession.shared.download(for: req, delegate: DropAuthOnRedirect())
            let dmg = work.appendingPathComponent(Self.assetName)
            try FileManager.default.moveItem(at: tmp, to: dmg)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateError.http(status, "téléchargement refusé") }

            state = .installing
            let staged = try await extractAndVerify(dmg: dmg, in: work, expected: release.version)

            let target = Bundle.main.bundleURL
            guard target.pathExtension == "app",
                  FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
            else { throw UpdateError.install("impossible d'écrire dans \(target.deletingLastPathComponent().path)") }

            let script = work.appendingPathComponent("remplacer.sh")
            try Self.swapScript.write(to: script, atomically: true, encoding: .utf8)
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
            state = .error(error.localizedDescription)
        }
    }

    private static let swapScript = """
    #!/bin/bash
    # $1 pid de l'app, $2 app installée, $3 nouvelle app, $4 dossier de travail
    while kill -0 "$1" 2>/dev/null; do sleep 0.3; done
    rm -rf "$2" && ditto "$3" "$2" && open "$2"
    rm -rf "$4"
    """

    private func extractAndVerify(dmg: URL, in work: URL, expected: String) async throws -> URL {
        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try await Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify",
                                                "-mountpoint", mount.path, dmg.path])
        let staged = work.appendingPathComponent("AutoCorrection.app")
        do {
            try await Self.run("/usr/bin/ditto", [mount.appendingPathComponent("AutoCorrection.app").path, staged.path])
        } catch {
            _ = try? await Self.run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            throw error
        }
        _ = try? await Self.run("/usr/bin/hdiutil", ["detach", "-force", mount.path])

        do {
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
            let info = try await Self.run("/usr/bin/codesign", ["-dv", "--verbose=2", staged.path])
            guard info.contains("TeamIdentifier=\(Self.teamID)") else {
                throw UpdateError.unsafe("l'application n'est pas signée par le bon développeur")
            }
            try await Self.run("/usr/sbin/spctl", ["-a", "-t", "exec", staged.path])
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
