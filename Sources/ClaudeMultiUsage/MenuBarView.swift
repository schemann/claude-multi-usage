import SwiftUI

/// Menu-bar label: shows the utilization of the pinned accounts (or the single
/// highest one when nothing is pinned), for the selected metric, tinted
/// red/orange when high. Falls back to the gauge icon when nothing is connected.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let entries = model.menuBarLabelEntries
        if entries.isEmpty {
            Image(systemName: "gauge.with.dots.needle.33percent")
        } else {
            let peak = entries.map(\.fraction).max() ?? 0
            let showInitials = model.labelShowsInitials
            HStack(spacing: 5) {
                Image(systemName: icon(peak))
                ForEach(entries) { e in
                    HStack(spacing: 2) {
                        if showInitials {
                            Text(e.initial).font(.system(size: 11, weight: .semibold))
                        }
                        Text("\(e.percent)%")
                    }
                    .foregroundStyle(tint(e.fraction))
                }
            }
        }
    }

    private func icon(_ fraction: Double) -> String {
        if fraction >= 0.9 { return "gauge.with.dots.needle.100percent" }
        if fraction >= 0.5 { return "gauge.with.dots.needle.67percent" }
        return "gauge.with.dots.needle.33percent"
    }

    private func tint(_ fraction: Double) -> Color {
        if fraction >= 0.9 { return .red }
        if fraction >= 0.8 { return .orange }
        return .primary
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude Usage").font(.headline)
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                .help(L("menu.refresh.help"))
            }

            if model.states.isEmpty {
                Text(model.isRefreshing ? L("menu.loading") : L("menu.noAccounts"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.states.enumerated()), id: \.element.id) { index, state in
                        AccountRow(
                            state: state,
                            isPinned: model.isPinned(state.id),
                            onRemove: { model.removeAccount(id: state.id) },
                            onRename: { model.renameAccount(id: state.id, to: $0) },
                            onTogglePin: { model.togglePin(id: state.id) }
                        )
                        .padding(.vertical, 8)
                        if index < model.states.count - 1 { Divider() }
                    }
                }
            }

            Button {
                model.beginAddAccount()
                AddAccountWindowController.shared.show(model: model)
            } label: {
                Label(L("menu.addAccount"), systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)

            if !model.states.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "menubar.arrow.up.rectangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L("menu.track")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $model.labelMetric) {
                            ForEach(model.availableMetrics, id: \.self) { m in
                                Text(metricName(m)).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }

                    HStack(spacing: 8) {
                        Text(L("menu.mode")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $model.labelMode) {
                            Text(L("mode.static")).tag(AppModel.labelModeStatic)
                            Text(L("mode.round")).tag(AppModel.labelModeRound)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 130)

                        if model.labelMode == AppModel.labelModeRound {
                            Picker("", selection: $model.rotateSeconds) {
                                ForEach(AppModel.rotateOptions, id: \.self) { Text(L("picker.seconds", $0)).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 66)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Picker("", selection: $model.refreshMinutes) {
                    ForEach(AppModel.refreshOptions, id: \.self) { Text(L("picker.minutes", $0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 90)

                Spacer()

                if let updated = model.lastUpdated {
                    Text(L("menu.lastUpdated", updated.formatted(date: .omitted, time: .shortened)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(L("menu.quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { model.refreshIfStale() }
    }

    /// Display name for a label metric key.
    private func metricName(_ metric: String) -> String {
        switch metric {
        case AppModel.metricPeak: return L("metric.peak")
        case AppModel.metricFiveHour: return "5h"
        case AppModel.metricSevenDay: return "7d"
        default: return metric // model display name, e.g. "Fable"
        }
    }
}

struct AccountRow: View {
    let state: AccountState
    let isPinned: Bool
    let onRemove: () -> Void
    let onRename: (String) -> Void
    let onTogglePin: () -> Void

    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header

            if let usage = state.usage {
                BarRow(label: "5h", fraction: usage.fiveHour?.fraction ?? 0, reset: usage.fiveHour?.resetsAtDate)
                BarRow(label: "7d", fraction: usage.sevenDay?.fraction ?? 0, reset: usage.sevenDay?.resetsAtDate)
                ForEach(usage.modelLimits, id: \.modelName) { limit in
                    BarRow(label: limit.modelName ?? L("model.fallback"), fraction: limit.fraction, reset: limit.resetsAtDate)
                }
            } else {
                Text(state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 15)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isSignedIn ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)

            if editing {
                TextField(L("row.name.placeholder"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .focused($nameFocused)
                    .onSubmit { commit() }
                    .frame(maxWidth: 180)
                Button(L("common.ok")) { commit() }.buttonStyle(.borderless).font(.caption)
                Button {
                    editing = false
                } label: { Image(systemName: "xmark").font(.caption) }
                .buttonStyle(.borderless)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.name).font(.subheadline).bold().lineLimit(1)
                    if let email = state.email, email != state.name {
                        Text(email).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if hovering {
                    Button {
                        draft = state.name
                        editing = true
                        nameFocused = true
                    } label: { Image(systemName: "pencil").font(.caption) }
                    .buttonStyle(.borderless)
                    .help(L("row.rename.help"))
                    Button(action: onRemove) {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(L("row.remove.help"))
                }
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(isPinned ? L("row.pin.off") : L("row.pin.on"))
                .opacity(isPinned || hovering ? 1 : 0.35)
            }
        }
    }

    private func commit() {
        onRename(draft)
        editing = false
    }
}

/// One compact usage line: label, bar, percent, relative reset.
struct BarRow: View {
    let label: String
    let fraction: Double
    let reset: Date?

    var body: some View {
        let pct = Int((fraction * 100).rounded())
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.monospaced())
                .frame(width: 46, alignment: .leading)
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(tint(fraction))
            Text("\(pct)%")
                .font(.caption.monospaced())
                .frame(width: 34, alignment: .trailing)
            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing)
                .help(reset.map { L("reset.tooltip", $0.formatted(date: .abbreviated, time: .shortened)) } ?? "")
        }
    }

    private var resetText: String {
        guard let reset else { return "" }
        return "↻ " + Self.relative.localizedString(for: reset, relativeTo: Date())
    }

    private func tint(_ fraction: Double) -> Color {
        if fraction > 0.9 { return .red }
        if fraction > 0.7 { return .orange }
        return .accentColor
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = .autoupdatingCurrent
        return f
    }()
}
