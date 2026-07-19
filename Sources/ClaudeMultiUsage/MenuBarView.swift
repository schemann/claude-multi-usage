import SwiftUI
import AppKit

/// Menu-bar label: draws small stacked usage bars for the pinned accounts (or
/// the single highest one when nothing is pinned) - one bar per window for the
/// selected metric, tinted orange/red when high. Falls back to the gauge icon
/// when nothing is connected.
///
/// SwiftUI shape views render as an empty label in the menu bar, so the bars are
/// rasterized into an NSImage (non-template, to keep their color).
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let groups = model.menuBarLabelGroups
        if groups.isEmpty {
            Image(systemName: "gauge.with.dots.needle.33percent")
        } else {
            HStack(spacing: 8) {
                ForEach(groups) { group in
                    if let image = MiniBars.render(group: group, dark: colorScheme == .dark) {
                        Image(nsImage: image)
                    }
                }
            }
        }
    }
}

/// Renders one account's label - the percent on top, its usage bars below - into
/// a single NSImage. The menu bar reorders side-by-side views and drops bare
/// SwiftUI shapes, so baking the whole stack into one non-template image is the
/// only reliable way to keep the vertical layout and the bar colors. The percent
/// text color follows the menu-bar appearance (passed in as `dark`).
enum MiniBars {
    static let barWidth: CGFloat = 28
    static let barHeight: CGFloat = 4
    static let barSpacing: CGFloat = 2
    static let labelWidth: CGFloat = 32   // fixed so the menu bar never shifts

    @MainActor
    static func render(group: AppModel.LabelGroup, dark: Bool) -> NSImage? {
        guard !group.bars.isEmpty else { return nil }
        let content = VStack(alignment: .center, spacing: 1) {
            Text("\(group.percent)%")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundColor(dark ? .white : .black)
                .lineLimit(1)
                .fixedSize()
            VStack(alignment: .center, spacing: barSpacing) {
                ForEach(Array(group.bars.enumerated()), id: \.offset) { _, f in
                    bar(f)
                }
            }
        }
        .frame(width: labelWidth)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    @ViewBuilder
    private static func bar(_ f: Double) -> some View {
        let clamped = max(0, min(1, f))
        ZStack(alignment: .leading) {
            Capsule().fill(Color(white: 0.55).opacity(0.45))
                .frame(width: barWidth, height: barHeight)
            Capsule().fill(tint(f))
                .frame(width: max(barHeight, barWidth * CGFloat(clamped)), height: barHeight)
        }
    }

    private static func tint(_ fraction: Double) -> Color {
        if fraction >= 0.9 { return Color(red: 1.0, green: 0.27, blue: 0.23) }   // red
        if fraction >= 0.8 { return Color(red: 1.0, green: 0.62, blue: 0.04) }   // orange
        return Color(red: 0.30, green: 0.55, blue: 1.0)                          // blue
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
                Image(systemName: "globe").font(.caption).foregroundStyle(.secondary)
                Text(L("menu.language")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $model.languageOverride) {
                    Text(L("language.system")).tag(AppModel.languageSystem)
                    Text("English").tag("en")
                    Text("Deutsch").tag("de")
                    Text("Français").tag("fr")
                    Text("Italiano").tag("it")
                    Text("Español").tag("es")
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            }

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
        // Rebuild the whole subtree on language change so every L() re-evaluates
        // (child rows take value-type inputs and would not otherwise re-render).
        .id(model.languageOverride)
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
        Self.relative.locale = LocalizationOverride.locale
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
