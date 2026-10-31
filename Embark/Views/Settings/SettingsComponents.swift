import SwiftUI

// The building blocks every Settings page is made of: a page with a large header, sections
// with a small label, and flat rows divided by hairlines. Nothing is boxed.

extension EnvironmentValues {
    /// The title of a row picked from Settings search, lit up for a moment.
    @Entry var settingsHighlight: String? = nil
}

/// A Settings page: the pane's icon, title and subtitle at the top, then its sections.
struct SettingsPage<Content: View>: View {
    let pane: SettingsPane
    @ViewBuilder var content: Content
    @Environment(\.settingsHighlight) private var highlight

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsHeader(pane: pane)
                    content
                }
                .padding(.horizontal, 44)
                .padding(.top, 34)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The page is a card below the title bar, so no edge fade where the title bar is.
            .scrollEdgeEffectHidden(true, for: .top)
            .onAppear { scroll(proxy) }
            .onChange(of: highlight) { scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let highlight else { return }
        Task { withAnimation(.snappy) { proxy.scrollTo(highlight, anchor: .center) } }
    }
}

struct SettingsHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 16) {
            SettingsIconTile(pane: pane, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(pane.title)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.3)
                Text(pane.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }
}

/// A group of rows under a small label, with a hairline between rows and none after the last.
struct SettingsSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .padding(.top, 26)
                    .padding(.bottom, 4)
            }
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    row
                    if row.id != rows.last?.id { Divider() }
                }
            }
        }
    }
}

/// One setting: an optional leading view, a title with a line of detail, and its control.
struct SettingRow<Leading: View, Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var control: Control
    @Environment(\.settingsHighlight) private var highlight

    init(_ title: String, detail: String? = nil,
         @ViewBuilder leading: () -> Leading = { EmptyView() },
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.leading = leading()
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 14) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 20)
            control
        }
        .padding(.vertical, 13)
        .background {
            if highlight == title {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.14))
                    .padding(.horizontal, -12)
                    .transition(.opacity)
            }
        }
        .id(title)
    }
}

/// A row whose control is a switch.
struct SettingToggle<Leading: View>: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    @ViewBuilder var leading: Leading

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>,
         @ViewBuilder leading: () -> Leading = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.leading = leading()
    }

    var body: some View {
        SettingRow(title, detail: detail, leading: { leading }) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}
