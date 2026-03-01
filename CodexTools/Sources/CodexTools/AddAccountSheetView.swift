import CodexToolsCore
import SwiftUI
import UniformTypeIdentifiers

struct AddAccountSheetView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case oauth = "ChatGPT Login"
        case importAuth = "Import auth.json"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .oauth
    @State private var path = ""
    @State private var showingImporter = false
    @State private var validationError: String?

    let onSubmit: (AddAccountInput) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UITheme.Spacing.s) {
            Text("Add Account")
                .font(UITheme.Font.title)

            Grid(alignment: .leading, horizontalSpacing: UITheme.Spacing.m, verticalSpacing: UITheme.Spacing.s) {
                GridRow {
                    formLabel("Mode")
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityIdentifier(A11yID.add.mode)
                }

                if mode == .importAuth {
                    GridRow {
                        formLabel("auth.json")
                        HStack(spacing: UITheme.Spacing.xs) {
                            TextField("Path to auth.json", text: $path)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .accessibilityIdentifier(A11yID.add.path)

                            Button("Browse...") {
                                showingImporter = true
                            }
                            .controlSize(.small)
                            .accessibilityIdentifier(A11yID.add.browse)
                        }
                    }
                }
            }

            if let validationError {
                Text(validationError)
                    .font(UITheme.Font.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: UITheme.Spacing.s) {
                Spacer()

                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(A11yID.add.cancel)

                if mode == .oauth {
                    Button("Copy Login Link") {
                        submitOAuth(.copyLink)
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier(A11yID.add.oauthCopyLink)

                    Button("Open Default Browser") {
                        submitOAuth(.openDefaultBrowser)
                    }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(A11yID.add.oauthOpenBrowser)
                } else {
                    Button("Add Account") {
                        submitImportAuth()
                    }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(A11yID.add.submit)
                }
            }
        }
        .padding(UITheme.Spacing.l)
        .frame(width: 440)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let first = urls.first
            else {
                return
            }
            path = first.path
        }
    }

    private func formLabel(_ label: String) -> some View {
        Text(label)
            .font(UITheme.Font.body)
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .leading)
    }

    private func submitOAuth(_ action: OAuthLoginAction) {
        validationError = nil
        onSubmit(.oauth(action))
    }

    private func submitImportAuth() {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            validationError = "Select an auth.json file"
            return
        }
        validationError = nil
        onSubmit(.importAuthJSON(path: trimmedPath))
    }
}
