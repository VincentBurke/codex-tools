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
        VStack(alignment: .leading, spacing: UITheme.AddSheet.sectionSpacing) {
            headerSection
            modeSection
            modeSpecificSection

            if let validationError {
                validationMessage(validationError)
            }

            Divider()
            footerSection
        }
        .padding(UITheme.Spacing.l)
        .frame(width: UITheme.AddSheet.width)
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: UITheme.AddSheet.headerSpacing) {
            Text("Add Account")
                .font(UITheme.Font.title)
        }
    }

    private var modeSection: some View {
        LabeledContent {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier(A11yID.add.mode)
        } label: {
            rowLabel("Mode")
        }
    }

    @ViewBuilder
    private var modeSpecificSection: some View {
        if mode == .oauth {
            EmptyView()
        } else {
            LabeledContent {
                HStack(spacing: UITheme.Spacing.xs) {
                    TextField("Path to auth.json", text: $path)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(A11yID.add.path)

                    Button("Browse...") {
                        showingImporter = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(A11yID.add.browse)
                }
            } label: {
                rowLabel("auth.json")
            }
        }
    }

    private var footerSection: some View {
        HStack(spacing: UITheme.AddSheet.footerSpacing) {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(A11yID.add.cancel)

            Spacer()

            if mode == .oauth {
                Button("Copy Link") {
                    submitOAuth(.copyLink)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(A11yID.add.oauthCopyLink)

                Button("Open Browser") {
                    submitOAuth(.openDefaultBrowser)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(A11yID.add.oauthOpenBrowser)
            } else {
                Button("Add Account") {
                    submitImportAuth()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(A11yID.add.submit)
            }
        }
        .controlSize(.regular)
    }

    private func validationMessage(_ message: String) -> some View {
        Label {
            Text(message)
                .font(UITheme.Font.caption)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .foregroundStyle(.red)
    }

    private func rowLabel(_ label: String) -> some View {
        Text(label)
            .font(UITheme.Font.body)
            .foregroundStyle(.secondary)
            .frame(width: UITheme.AddSheet.labelWidth, alignment: .leading)
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
