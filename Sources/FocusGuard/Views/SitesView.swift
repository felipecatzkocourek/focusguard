import SwiftUI

struct SitesView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Sites to block")
            Text("Paste a site or any link from it. www. and mobile (m.) versions are blocked too.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("instagram.com", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            List {
                ForEach(model.configuration.blockedDomains, id: \.self) { domain in
                    HStack {
                        Text(domain).font(.body.monospaced())
                        Spacer()
                        Button {
                            Task { await model.removeDomain(domain) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(model.isLocked ? Color.secondary : Color.red)
                        .disabled(model.isLocked)
                        .help(model.isLocked ? "Sites can't be removed while blocking is on" : "Remove \(domain)")
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            if BrowserTabs.isFirefoxInstalled {
                Label("Firefox: restart it once after adding a site, so it picks up the new DNS-over-HTTPS exception.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if model.isLocked {
                Label("While blocking is on you can add sites, but not remove them.", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }

    private func add() {
        let text = input
        Task {
            if await model.addDomain(text) != nil {
                input = ""
                error = nil
            } else {
                error = "“\(text.trimmingCharacters(in: .whitespaces))” doesn't look like a website."
            }
        }
    }
}
