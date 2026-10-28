import SwiftUI

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: Color(red: 0.35, green: 0.4, blue: 0.95).opacity(0.35), radius: 24, y: 12)
            Text("Embark")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .padding(.top, 14)
            Text("Version \(version) · \(engine) engine")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
                .id("Version")
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    link("Source on GitHub", "https://github.com/chiranjeebhub/embark-browser")
                    link("MIT License", "https://github.com/chiranjeebhub/embark-browser/blob/main/LICENSE")
                    link("Report a problem", "https://github.com/chiranjeebhub/embark-browser/issues")
                }
            }
            .padding(.top, 22)
            Text("Free and open source. Made for the Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 24)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func link(_ title: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Text(title)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .contentShape(.capsule)
        }
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private var engine: String {
        #if ENGINE_CEF
        "Chromium"
        #else
        "WebKit"
        #endif
    }
}
