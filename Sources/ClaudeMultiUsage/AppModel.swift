import Foundation
import SwiftUI
import AppKit

struct AccountState: Identifiable {
    let id: String
    let name: String        // display name (custom or email)
    let email: String?      // canonical email, shown to disambiguate
    var status: String
    var usage: UsageResponse?

    var isSignedIn: Bool { usage != nil }

    /// Peak utilization fraction across all windows (5h, 7d, model-scoped).
    var peakFraction: Double {
        guard let usage else { return 0 }
        var peak = max(usage.fiveHour?.fraction ?? 0, usage.sevenDay?.fraction ?? 0)
        for limit in usage.modelLimits { peak = max(peak, limit.fraction) }
        return peak
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var states: [AccountState] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    // Add-account (OAuth) flow state
    @Published var isAddingAccount = false
    @Published var pendingCode = ""
    @Published var addError: String?
    @Published private(set) var isExchanging = false

    @Published var refreshMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes")
            scheduleTimer()
        }
    }

    static let refreshOptions = [15, 30, 60]

    /// Utilization thresholds (%) that trigger a warning notification.
    static let warnThresholds = [90, 80]

    private let store = AccountStore()
    private var accounts: [StoredAccount] = []
    private var pkce: OAuthService.PKCE?
    private var timer: Timer?
    private var firedThresholds: Set<String>

    private init() {
        let stored = UserDefaults.standard.integer(forKey: "refreshMinutes")
        refreshMinutes = Self.refreshOptions.contains(stored) ? stored : 30
        firedThresholds = Set(UserDefaults.standard.stringArray(forKey: "firedThresholds") ?? [])
        accounts = store.load()
    }

    /// Highest utilization across all signed-in accounts (both windows), for the
    /// menu-bar label. nil when nothing is connected yet.
    var maxUtilizationPercent: Int? {
        let fractions = states.filter { $0.isSignedIn }.map { $0.peakFraction }
        guard let peak = fractions.max() else { return nil }
        return Int((peak * 100).rounded())
    }

    func start() {
        Task { await ResetNotifier.requestAuthorization() }
        refresh()
        scheduleTimer()
    }

    func refresh() { Task { await reload() } }

    /// Refresh when the popover opens if the data is older than `maxAge`, so a
    /// freshly opened menu shows current numbers without a manual click.
    func refreshIfStale(maxAge: TimeInterval = 90) {
        guard !isRefreshing else { return }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge { return }
        refresh()
    }

    var hasAccounts: Bool { !accounts.isEmpty }

    // MARK: - Add account (own OAuth session)

    func beginAddAccount() {
        let pkce = OAuthService.makePKCE()
        self.pkce = pkce
        pendingCode = ""
        addError = nil
        isAddingAccount = true
        NSWorkspace.shared.open(OAuthService.authorizeURL(pkce))
    }

    /// Pull the code straight from the clipboard, then exchange it — so the user
    /// only has to copy in the browser, no manual paste.
    func pasteAndSubmit() {
        if let clip = NSPasteboard.general.string(forType: .string) {
            let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { pendingCode = trimmed }
        }
        submitCode()
    }

    /// Prefill the field if the clipboard already looks like an OAuth code.
    func prefillFromClipboard() {
        guard pendingCode.isEmpty,
              let clip = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeCode = !trimmed.contains(" ") && (trimmed.contains("#") || trimmed.count > 30)
        if looksLikeCode { pendingCode = trimmed }
    }

    func submitCode() {
        guard let pkce else { addError = L("error.noLogin"); return }
        let raw = pendingCode
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            addError = L("error.noCode"); return
        }
        isExchanging = true
        addError = nil
        Task {
            defer { isExchanging = false }
            guard let credentials = await OAuthService.exchangeCode(raw, pkce: pkce) else {
                addError = L("error.invalidCode")
                return
            }
            let email = await OAuthService.fetchEmail(token: credentials.accessToken)
            let account = StoredAccount(id: UUID().uuidString, email: email, credentials: credentials)
            accounts.append(account)
            store.save(accounts)
            self.pkce = nil
            isAddingAccount = false
            pendingCode = ""
            await reload()
        }
    }

    func cancelAddAccount() {
        pkce = nil
        isAddingAccount = false
        pendingCode = ""
        addError = nil
    }

    func removeAccount(id: String) {
        accounts.removeAll { $0.id == id }
        store.save(accounts)
        states.removeAll { $0.id == id }
        refresh()
    }

    /// Rename an account's display name. Empty input clears the custom name and
    /// falls back to the email.
    func renameAccount(id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].displayName = trimmed.isEmpty ? nil : trimmed
        store.save(accounts)
        let name = accounts[index].title
        let email = accounts[index].email
        if let sIndex = states.firstIndex(where: { $0.id == id }) {
            let old = states[sIndex]
            states[sIndex] = AccountState(id: old.id, name: name, email: email, status: old.status, usage: old.usage)
        }
    }

    // MARK: - Polling

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: Double(refreshMinutes * 60), repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func reload() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var updated = accounts
        var newStates: [AccountState] = []

        for index in updated.indices {
            var account = updated[index]

            // Proactive refresh when close to expiry.
            if account.credentials.needsRefresh() {
                if case .success(let fresh) = await OAuthService.refresh(account.credentials) {
                    account.credentials = fresh
                    updated[index] = account
                }
            }

            // Backfill the email once for accounts that predate email storage.
            if account.email == nil {
                if let email = await OAuthService.fetchEmail(token: account.credentials.accessToken) {
                    account.email = email
                    updated[index] = account
                }
            }

            func state(_ status: String, _ usage: UsageResponse?) -> AccountState {
                AccountState(id: account.id, name: account.title, email: account.email, status: status, usage: usage)
            }

            switch await UsageClient.fetch(token: account.credentials.accessToken) {
            case .ok(let usage):
                newStates.append(state("ok", usage))

            case .unauthorized:
                // One reactive refresh attempt, then retry once.
                switch await OAuthService.refresh(account.credentials) {
                case .success(let fresh):
                    account.credentials = fresh
                    updated[index] = account
                    if case .ok(let usage) = await UsageClient.fetch(token: fresh.accessToken) {
                        newStates.append(state("ok", usage))
                    } else {
                        newStates.append(state(L("status.unavailable"), nil))
                    }
                case .permanentFailure:
                    newStates.append(state(L("status.expired"), nil))
                case .transientFailure:
                    newStates.append(state(L("status.refreshFailed"), nil))
                }

            case .error(let message):
                newStates.append(state(message, nil))
            }
        }

        accounts = updated
        store.save(updated)
        states = newStates
        lastUpdated = Date()
        ResetNotifier.schedule(for: newStates)
        checkThresholds(newStates)
    }

    // MARK: - Threshold warnings

    private func checkThresholds(_ states: [AccountState]) {
        // Drop keys for windows whose reset time has already passed.
        let now = Date().timeIntervalSince1970
        firedThresholds = firedThresholds.filter { key in
            guard let epoch = key.split(separator: ":").last.flatMap({ Double($0) }) else { return true }
            return epoch > now
        }

        for state in states {
            guard let usage = state.usage else { continue }
            checkWindow(state.id, state.name, "5h", usage.fiveHour?.utilization, usage.fiveHour?.resetsAtDate)
            checkWindow(state.id, state.name, "7d", usage.sevenDay?.utilization, usage.sevenDay?.resetsAtDate)
            for limit in usage.modelLimits {
                checkWindow(state.id, state.name, limit.modelName ?? "Modell", limit.percent, limit.resetsAtDate)
            }
        }

        UserDefaults.standard.set(Array(firedThresholds), forKey: "firedThresholds")
    }

    private func checkWindow(_ accId: String, _ label: String, _ window: String, _ utilization: Double?, _ resetsAt: Date?) {
        guard let util = utilization else { return }
        let resetKey = resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "na"

        for threshold in Self.warnThresholds { // highest first
            guard util >= Double(threshold) else { continue }
            let key = "thresh:\(accId):\(window):\(threshold):\(resetKey)"
            if !firedThresholds.contains(key) {
                firedThresholds.insert(key)
                ResetNotifier.fire(
                    id: key,
                    title: L("notif.threshold.title"),
                    body: L("notif.threshold.body", label, window, Int(util.rounded()))
                )
            }
            break // only the highest crossed threshold fires
        }
    }
}
