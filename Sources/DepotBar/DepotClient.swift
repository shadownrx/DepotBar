import Foundation

// MARK: - Models (mirror `depot ci workflow list -o json`)

struct JobCounts: Codable, Sendable {
    var total: Int = 0
    var queued: Int = 0
    var waiting: Int = 0
    var running: Int = 0
    var finished: Int = 0
    var failed: Int = 0
    var cancelled: Int = 0
    var skipped: Int = 0
}

struct DepotWorkflow: Codable, Sendable, Identifiable {
    var workflow_id: String
    var name: String
    var workflow_path: String
    var repo: String
    var status: String
    var trigger: String
    var run_id: String
    var sha: String
    var head_sha: String
    var created_at: String
    var job_counts: JobCounts
    // Enriched post-list via `depot ci workflow show` (nil when detail is unavailable).
    var ref: String? = nil
    var started_at: String? = nil
    var finished_at: String? = nil
    // Enriched post-list via the GitHub API (nil when `gh` is missing or the lookup fails).
    // Display-ready: "@login" when the GitHub user is known, else the raw commit author name.
    var author: String? = nil

    var id: String { workflow_id }

    var isRunning: Bool {
        status == "running" || status == "queued"
            || job_counts.running > 0 || job_counts.queued > 0 || job_counts.waiting > 0
    }

    var isFailed: Bool { status == "failed" || status == "cancelled" || job_counts.failed > 0 }
    var isFinished: Bool { status == "finished" && job_counts.failed == 0 }

    var shortRepo: String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }

    var shortSHA: String { String(sha.prefix(7)) }

    var createdAt: Date? {
        ISO8601DateFormatter().date(from: created_at)
    }

    func relativeTime(now: Date = Date()) -> String {
        guard let date = createdAt else { return "" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<60: return "\(seconds)s ago"
        case 60..<3600: return "\(seconds / 60)m ago"
        case 3600..<86400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86400)d ago"
        }
    }

    /// PR number parsed from refs like `refs/pull/317/merge` (nil for push triggers).
    var prNumber: Int? {
        guard let ref else { return nil }
        let parts = ref.split(separator: "/")
        guard parts.count >= 3, parts[0] == "refs", parts[1] == "pull",
              let number = Int(parts[2])
        else { return nil }
        return number
    }

    var startedAt: Date? {
        started_at.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    var finishedAt: Date? {
        finished_at.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// Seconds from workflow start to finish (or to now while still running).
    func elapsedSeconds(now: Date = Date()) -> Int? {
        guard let start = startedAt else { return nil }
        let end = finishedAt ?? now
        return max(0, Int(end.timeIntervalSince(start)))
    }

    /// Bare duration ("8m22s") — the row icon already says running vs finished.
    func durationText(now: Date = Date()) -> String? {
        guard let seconds = elapsedSeconds(now: now) else { return nil }
        return Self.formatDuration(seconds)
    }

    static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 {
            return String(format: "%dm%02ds", seconds / 60, seconds % 60)
        }
        return String(format: "%dh%02dm", seconds / 3600, (seconds % 3600) / 60)
    }

}

// MARK: - Detail models (mirror `depot ci workflow show -o json`, subset we need)

struct WorkflowShowOutput: Codable, Sendable {
    struct RunInfo: Codable, Sendable {
        var ref: String?
    }
    struct WorkflowInfo: Codable, Sendable {
        var started_at: String?
        var finished_at: String?
    }
    var run: RunInfo?
    var workflow: WorkflowInfo?
}

// MARK: - Author models (mirror `gh api repos/{owner}/{repo}/commits/{sha} --jq ...`, subset we need)

/// Tiny projection of a GitHub commit: `{"login": .author.login, "name": .commit.author.name}`.
struct GitHubAuthorOutput: Codable, Sendable {
    var login: String?
    var name: String?
}

enum GitHubAuthor {
    /// "@login" when the GitHub user is linked, else the raw commit author name, else nil.
    static func displayName(from output: GitHubAuthorOutput) -> String? {
        if let login = output.login, !login.isEmpty {
            return "@\(login)"
        }
        if let name = output.name, !name.isEmpty {
            return name
        }
        return nil
    }
}

/// In-memory cache of resolved authors, keyed by `"repo@sha"`. Commits are
/// immutable, so entries never expire for the life of the process.
actor AuthorCache {
    private var stored: [String: String?] = [:]

    func lookup(_ key: String) -> (hit: Bool, author: String?) {
        guard let author = stored[key] else { return (false, nil) }
        return (true, author)
    }

    func store(_ author: String?, for key: String) {
        stored[key] = author
    }
}

// MARK: - GitHub client (shells out to the `gh` CLI, reusing its auth)

struct GitHubClient: Sendable {
    let cliPath: String

    init() throws {
        self.cliPath = try Self.resolveCLIPath()
    }

    /// Locate the `gh` binary (Homebrew + standard paths + PATH lookup).
    static func resolveCLIPath() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "\(NSHomeDirectory())/.local/bin/gh",
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to a login-shell PATH lookup.
        if let found = try? DepotClient.shellOut("/bin/zsh", ["-l", "-c", "command -v gh"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !found.isEmpty, fm.isExecutableFile(atPath: found)
        {
            return found
        }
        throw DepotError.cliNotFound
    }

    /// Commit author for `repo` at `sha`, display-ready (`@login` or plain name).
    /// Returns nil when GitHub knows no author (or the repo/SHA is unknown).
    func fetchAuthorDisplayName(repo: String, sha: String) async throws -> String? {
        let data = try await DepotClient.runBinary(
            executable: cliPath,
            arguments: ["api", "repos/\(repo)/commits/\(sha)", "--jq", "{login: .author.login, name: .commit.author.name}"]
        )
        let output = try JSONDecoder().decode(GitHubAuthorOutput.self, from: data)
        return GitHubAuthor.displayName(from: output)
    }
}

// MARK: - Client (shells out to the Depot CLI, reusing its auth)

enum DepotError: Error, Sendable {
    case cliNotFound
    case failed(exitCode: Int32, message: String)
    case decodeError(String)
}

struct DepotClient: Sendable {
    let cliPath: String
    let orgID: String?
    let count: Int
    private let authorCache = AuthorCache()
    /// Resolved API token (`DEPOT_TOKEN` env wins, else the Keychain token).
    /// Exported to the `depot` child process; nil means "use `depot login`".
    let apiToken: String?
    private let baseEnvironment: [String: String]

    init(
        count: Int = 5,
        storage: TokenStorage = KeychainTokenStorage(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        self.cliPath = try Self.resolveCLIPath()
        self.orgID = Self.resolveOrgID()
        self.count = count
        self.baseEnvironment = environment
        self.apiToken = TokenAuth.resolve(
            keychainToken: try? storage.load(),
            environment: environment
        )
    }

    /// Where auth comes from — shown in the menu/logs, never the token itself.
    var authSource: String { apiToken == nil ? "Depot CLI login" : "API token" }

    /// Locate the `depot` binary (Homebrew + standard paths + PATH lookup).
    static func resolveCLIPath() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/depot",
            "/usr/local/bin/depot",
            "\(NSHomeDirectory())/.local/bin/depot",
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to a login-shell PATH lookup.
        if let found = try? shellOut("/bin/zsh", ["-l", "-c", "command -v depot"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !found.isEmpty, fm.isExecutableFile(atPath: found)
        {
            return found
        }
        throw DepotError.cliNotFound
    }

    /// Read the current org id from the CLI's own settings (used for web URLs).
    static func resolveOrgID() -> String? {
        if let env = ProcessInfo.processInfo.environment["DEPOT_ORG_ID"], !env.isEmpty {
            return env
        }
        let path = "\(NSHomeDirectory())/Library/Application Support/depot/depot.yaml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("org_id:") {
                let value = trimmed.dropFirst("org_id:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    func fetchWorkflows() async throws -> [DepotWorkflow] {
        let data = try await run(arguments: ["ci", "workflow", "list", "-n", "\(count)", "-o", "json"])
        let listed: [DepotWorkflow]
        do {
            listed = try JSONDecoder().decode([DepotWorkflow].self, from: data)
        } catch {
            throw DepotError.decodeError(error.localizedDescription)
        }
        // Enrich each workflow with timing + PR ref via `show`, concurrently.
        // A detail failure for one workflow must not fail the whole refresh.
        return await withTaskGroup(of: (Int, WorkflowShowOutput?).self) { group in
            for (index, workflow) in listed.enumerated() {
                group.addTask {
                    let detail = try? await self.fetchDetail(for: workflow.workflow_id)
                    return (index, detail)
                }
            }
            var enriched = listed
            for await (index, detail) in group {
                if let detail {
                    enriched[index].ref = detail.run?.ref
                    enriched[index].started_at = detail.workflow?.started_at
                    enriched[index].finished_at = detail.workflow?.finished_at
                }
            }
            return await self.enrichAuthors(enriched)
        }
    }

    /// Fill `author` for each workflow from its GitHub commit. Best-effort:
    /// a missing `gh` CLI or a failed lookup leaves the author nil and never
    /// fails the refresh. Resolved authors are cached by `repo@sha`.
    func enrichAuthors(_ workflows: [DepotWorkflow]) async -> [DepotWorkflow] {
        guard let github = try? GitHubClient() else { return workflows }
        let cache = authorCache
        let authorsByKey = await withTaskGroup(of: (String, String?).self) { group in
            var seen = Set<String>()
            for workflow in workflows {
                let sha = workflow.head_sha.isEmpty ? workflow.sha : workflow.head_sha
                guard !workflow.repo.isEmpty, !sha.isEmpty else { continue }
                let key = "\(workflow.repo)@\(sha)"
                guard seen.insert(key).inserted else { continue }
                group.addTask {
                    let cached = await cache.lookup(key)
                    if cached.hit {
                        return (key, cached.author)
                    }
                    let author = try? await github.fetchAuthorDisplayName(repo: workflow.repo, sha: sha)
                    await cache.store(author, for: key)
                    return (key, author)
                }
            }
            var collected: [String: String?] = [:]
            for await (key, author) in group {
                collected[key] = author
            }
            return collected
        }
        var enriched = workflows
        for index in enriched.indices {
            let workflow = enriched[index]
            let sha = workflow.head_sha.isEmpty ? workflow.sha : workflow.head_sha
            if let author = authorsByKey["\(workflow.repo)@\(sha)"] {
                enriched[index].author = author
            }
        }
        return enriched
    }

    func fetchDetail(for workflowID: String) async throws -> WorkflowShowOutput {
        let data = try await run(arguments: ["ci", "workflow", "show", workflowID, "-o", "json"])
        return try JSONDecoder().decode(WorkflowShowOutput.self, from: data)
    }

    func dashboardURL() -> URL? {
        guard let org = orgID else { return URL(string: "https://depot.dev/orgs") }
        return URL(string: "https://depot.dev/orgs/\(org)/workflows/")
    }

    func workflowURL(for workflow: DepotWorkflow) -> URL? {
        guard let org = orgID else { return dashboardURL() }
        return URL(string: "https://depot.dev/orgs/\(org)/workflows/\(workflow.workflow_id)")
    }

    // MARK: - Process plumbing

    private func run(arguments: [String]) async throws -> Data {
        let childEnvironment = TokenAuth.childEnvironment(base: self.baseEnvironment, token: self.apiToken)
        return try await Self.runBinary(executable: cliPath, arguments: arguments, environment: childEnvironment)
    }

    static func runBinary(executable: String, arguments: [String], environment: [String: String]? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let environment {
                    process.environment = environment
                }
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: DepotError.failed(exitCode: -1, message: error.localizedDescription))
                    return
                }
                process.waitUntilExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus != 0 {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
                    continuation.resume(throwing: DepotError.failed(exitCode: process.terminationStatus, message: message))
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    static func shellOut(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
