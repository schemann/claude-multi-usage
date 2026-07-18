import SwiftUI

/// Menu-bar label: highest utilization across all accounts as a percentage,
/// tinted red/orange when high, or the gauge icon when nothing is connected.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let pct = model.maxUtilizationPercent {
            HStack(spacing: 3) {
                Image(systemName: icon(pct))
                Text("\(pct)%")
            }
            .foregroundStyle(tint(pct))
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }

    private func icon(_ pct: Int) -> String {
        if pct >= 90 { return "gauge.with.dots.needle.100percent" }
        if pct >= 50 { return "gauge.with.dots.needle.67percent" }
        return "gauge.with.dots.needle.33percent"
    }

    private func tint(_ pct: Int) -> Color {
        if pct >= 90 { return .red }
        if pct >= 80 { return .orange }
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
                            onRemove: { model.removeAccount(id: state.id) },
                            onRename: { model.renameAccount(id: state.id, to: $0) }
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
}

struct AccountRow: View {
    let state: AccountState
    let onRemove: () -> Void
    let onRename: (String) -> Void

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
