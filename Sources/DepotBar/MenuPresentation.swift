import Foundation

// MARK: - Menu presentation (single source of truth for what the user reads)

enum MenuPresentation {
    static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    static func spinner(at index: Int) -> String {
        spinnerFrames[index % spinnerFrames.count]
    }

    static func rowTitle(for workflow: DepotWorkflow, spinnerIndex: Int, now: Date = Date()) -> String {
        let icon: String
        if workflow.isRunning {
            icon = spinner(at: spinnerIndex)
        } else if workflow.isFailed {
            icon = "✗"
        } else {
            icon = "✓"
        }
        var parts = ["\(workflow.name) — \(workflow.shortRepo)"]
        if let author = workflow.author, !author.isEmpty {
            parts.append(author)
        }
        if let pr = workflow.prNumber {
            parts.append("#\(pr)")
        }
        parts.append(workflow.relativeTime(now: now))
        if let duration = workflow.durationText(now: now) {
            parts.append(duration)
        }
        return "\(icon)  " + parts.joined(separator: " · ")
    }

    static func footerTitle(isFetching: Bool, lastFetch: Date?, lastError: String?, spinnerIndex: Int, now: Date = Date()) -> String {
        if isFetching {
            return "\(spinner(at: spinnerIndex))  Updating…"
        } else if let lastFetch {
            let seconds = max(0, Int(now.timeIntervalSince(lastFetch)))
            return seconds < 5 ? "Updated just now" : "Updated \(seconds)s ago · refreshes every 30s"
        } else if lastError != nil {
            return "Last update failed"
        } else {
            return ""
        }
    }

    /// Describes the menu bar icon state: `.spinner` (animated) or an SF Symbol name.
    enum StatusIcon: CustomStringConvertible {
        case spinner(frame: String)
        case symbol(name: String)

        var description: String {
            switch self {
            case .spinner(let frame): return "spinner(\(frame))"
            case .symbol(let name): return "symbol(\(name))"
            }
        }
    }

    /// Grace period before a refresh shows the spinner. Routine fetches take
    /// ~1s, so without this the icon would flash every 30s refresh (noise).
    /// Only genuinely slow/stuck fetches — or actually-running workflows —
    /// spin the menu bar icon.
    static let slowFetchThreshold: TimeInterval = 2.0

    static func statusIcon(
        workflows: [DepotWorkflow], isFetching: Bool, fetchStartedAt: Date?,
        lastError: String?, spinnerIndex: Int, now: Date = Date()
    ) -> StatusIcon {
        let slowFetch: Bool
        if !isFetching {
            slowFetch = false
        } else if let started = fetchStartedAt {
            slowFetch = now.timeIntervalSince(started) > slowFetchThreshold
        } else {
            slowFetch = true
        }
        if slowFetch || workflows.contains(where: { $0.isRunning }) {
            return .spinner(frame: spinner(at: spinnerIndex))
        } else if workflows.contains(where: { $0.isFailed }) {
            return .symbol(name: "xmark.circle.fill")
        } else if !workflows.isEmpty {
            return .symbol(name: "checkmark.circle.fill")
        } else if lastError != nil {
            return .symbol(name: "exclamationmark.triangle")
        } else {
            return .symbol(name: "shippingbox")
        }
    }
}

// MARK: - Debug dump (`DepotBar --dump-menu`): prints exactly what the menu shows

enum MenuDump {
    static func runAndExit() -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await run()
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }

    private static func run() async {
        let now = Date()
        do {
            let client = try DepotClient(count: 5)
            print("auth: \(client.authSource)")
            let workflows = try await client.fetchWorkflows()
            print("theme: \(AppConfig.load().theme.rawValue) (config: \(AppConfig.fileURL.path))")
            print("menu-bar icon: \(MenuPresentation.statusIcon(workflows: workflows, isFetching: false, fetchStartedAt: nil, lastError: nil, spinnerIndex: 0))")
            print("---")
            print("Depot CI")
            print("---")
            for workflow in workflows {
                print(MenuPresentation.rowTitle(for: workflow, spinnerIndex: 0, now: now))
                print("    -> \(client.workflowURL(for: workflow)?.absoluteString ?? "?")")
            }
            print("---")
            print(MenuPresentation.footerTitle(isFetching: false, lastFetch: now, lastError: nil, spinnerIndex: 0, now: now))
            print("Refresh now")
            print("Open Depot dashboard -> \(client.dashboardURL()?.absoluteString ?? "?")")
            print("Launch at Login")
            print("---")
            print("Quit DepotBar")
        } catch {
            print("DUMP FAILED: \(error)")
            exit(1)
        }
    }
}
