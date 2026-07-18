import SwiftUI

struct AddAccountView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("add.title")).font(.title3).bold()

            Text(L("add.instructions"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.pasteAndSubmit()
            } label: {
                if model.isExchanging {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("add.connectClipboard"), systemImage: "clipboard")
                }
            }
            .controlSize(.large)
            .disabled(model.isExchanging)

            DisclosureGroup(L("add.manual")) {
                TextField(L("add.codePlaceholder"), text: $model.pendingCode, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .onSubmit { model.submitCode() }
            }
            .font(.caption)

            if let error = model.addError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button(L("add.reopenBrowser")) { model.beginAddAccount() }
                    .buttonStyle(.link)
                Spacer()
                Button(L("add.cancel")) {
                    model.cancelAddAccount()
                    AddAccountWindowController.shared.close()
                }
                Button {
                    model.submitCode()
                } label: {
                    if model.isExchanging {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("add.connect"))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isExchanging)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { model.prefillFromClipboard() }
        .onChange(of: model.isAddingAccount) { adding in
            if !adding { AddAccountWindowController.shared.close() } // closes after a successful connect
        }
    }
}
