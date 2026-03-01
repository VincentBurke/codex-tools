import CodexToolsCore
import SwiftUI

struct StatusPopoverView: View {
    private enum FooterAction: Hashable {
        case manage
        case closeCodex
        case quit
    }

    @ObservedObject var controller: AppController
    @State private var selectedAccountID: String?
    @State private var hoveredAccountID: String?
    @State private var hoveredFooterAction: FooterAction?

    private var accounts: [StatusAccountEntry] {
        controller.statusSnapshot.accounts
    }

    private var nextBestRecommendation: NextBestRecommendation? {
        makeNextBestRecommendation(from: accounts)
    }

    var body: some View {
        VStack(spacing: UITheme.Spacing.s) {
            header
            nextBestSection
            Divider()
            accountList
            footer
        }
        .padding(UITheme.Spacing.s)
        .frame(width: UITheme.Popover.width)
        .background(keyboardShortcuts)
        .onMoveCommand(perform: handleMoveCommand)
        .onExitCommand {
            controller.closePopoverFromKeyboard()
        }
        .onAppear {
            syncSelection()
        }
        .onChange(of: controller.statusSnapshot.accounts) { _, _ in
            syncSelection()
        }
    }

    private var header: some View {
        Button {
            controller.sendStatusCommand(.refreshAll)
        } label: {
            HStack(spacing: UITheme.Spacing.xs) {
                Text(controller.statusSnapshot.isRefreshingUsage ? "Refreshing usage..." : "Refresh All")
                    .font(UITheme.Font.bodyStrong)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .disabled(controller.statusSnapshot.isRefreshingUsage)
        .accessibilityIdentifier(A11yID.popover.refresh)
    }

    @ViewBuilder
    private var nextBestSection: some View {
        if let recommendation = nextBestRecommendation {
            VStack(alignment: .leading, spacing: UITheme.Spacing.xs) {
                HStack {
                    Text("Next Best")
                        .font(UITheme.Font.captionStrong)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                HStack(spacing: UITheme.Spacing.s) {
                    VStack(alignment: .leading, spacing: UITheme.Spacing.xxs) {
                        Text(recommendation.name)
                            .font(UITheme.Font.bodyStrong)
                            .lineLimit(1)

                        Text("Weekly \(recommendation.weeklyText) · 5h \(recommendation.fiveHourText)")
                            .font(UITheme.Font.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button("Switch") {
                        controller.switchToAccountFromPopover(recommendation.accountID)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.statusSnapshot.canSwitch)
                    .accessibilityIdentifier(A11yID.popover.nextBestSwitch)
                }

                if !controller.statusSnapshot.canSwitch {
                    Text("Switching blocked while Codex processes are running.")
                        .font(UITheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(A11yID.popover.nextBestUnavailable)
                }
            }
            .padding(UITheme.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: UITheme.CornerRadius.medium)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UITheme.CornerRadius.medium)
                    .stroke(severityAccentColor(recommendation.severity).opacity(0.35), lineWidth: 1)
            )
            .accessibilityIdentifier(A11yID.popover.nextBestCard)
        } else {
            HStack {
                Text("No recommended target")
                    .font(UITheme.Font.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    private var accountList: some View {
        ScrollView {
            LazyVStack(spacing: UITheme.Spacing.xxs) {
                ForEach(accounts, id: \.id) { account in
                    accountRow(account)
                }
            }
        }
        .frame(maxHeight: UITheme.Popover.maxListHeight)
    }

    private func accountRow(_ account: StatusAccountEntry) -> some View {
        let model = makeStatusRowDisplayModel(account)
        let selected = selectedAccountID == account.id
        let enabled = !account.isActive && controller.statusSnapshot.canSwitch

        return Button {
            selectedAccountID = account.id
            controller.sendStatusCommand(.switchAccount(account.id))
        } label: {
            HStack(spacing: UITheme.Spacing.s) {
                Circle()
                    .fill(model.isActive ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: UITheme.Spacing.xxs) {
                    Text(model.name)
                        .font(UITheme.Font.bodyStrong)
                        .lineLimit(1)

                    Text(model.statusLine)
                        .font(UITheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(model.weeklyText)
                    .font(UITheme.Font.captionStrong)
                    .foregroundStyle(model.severity == .healthy ? .secondary : severityAccentColor(model.severity))
            }
            .padding(.horizontal, UITheme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: UITheme.Popover.rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UITheme.CornerRadius.small)
                    .fill(rowBackgroundColor(selected: selected, hovered: hoveredAccountID == account.id, enabled: enabled))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { isHovering in
            guard enabled else {
                if hoveredAccountID == account.id {
                    hoveredAccountID = nil
                }
                return
            }

            if isHovering {
                hoveredAccountID = account.id
            } else if hoveredAccountID == account.id {
                hoveredAccountID = nil
            }
        }
        .accessibilityIdentifier(A11yID.popover.row(account.id))
    }

    private var footer: some View {
        VStack(spacing: UITheme.Spacing.xxs) {
            Divider()

            menuButton("Manage Accounts...", a11yID: A11yID.popover.manage) {
                controller.sendStatusCommand(.manageAccounts)
            }

            menuButton(
                "Close Codex",
                disabled: controller.statusSnapshot.processCount == 0,
                footerAction: .closeCodex,
                a11yID: A11yID.popover.closeCodex
            ) {
                controller.sendStatusCommand(.closeCodex)
            }

            Divider()

            menuButton("Quit codex-tools", footerAction: .quit, a11yID: A11yID.popover.quit) {
                controller.sendStatusCommand(.quitApp)
            }
        }
    }

    private func menuButton(
        _ title: String,
        disabled: Bool = false,
        footerAction: FooterAction = .manage,
        a11yID: String,
        action: @escaping () -> Void
    ) -> some View {
        let hovered = hoveredFooterAction == footerAction

        return Button(action: action) {
            HStack {
                Text(title)
                    .font(UITheme.Font.body)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, UITheme.Spacing.xs)
            .frame(minHeight: UITheme.Popover.rowHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: UITheme.CornerRadius.small)
                    .fill(menuBackgroundColor(hovered: hovered, disabled: disabled))
            )
            .foregroundStyle(menuForegroundColor(hovered: hovered, disabled: disabled))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovering in
            guard !disabled else {
                if hoveredFooterAction == footerAction {
                    hoveredFooterAction = nil
                }
                return
            }

            if isHovering {
                hoveredFooterAction = footerAction
            } else if hoveredFooterAction == footerAction {
                hoveredFooterAction = nil
            }
        }
        .accessibilityIdentifier(a11yID)
    }

    private var keyboardShortcuts: some View {
        HStack(spacing: 0) {
            keyboardShortcut(.return) {
                triggerSwitchSelected()
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0.001)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func keyboardShortcut(_ key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button("") {
            action()
        }
        .keyboardShortcut(key, modifiers: [])
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            moveSelection(.moveUp)
        case .down:
            moveSelection(.moveDown)
        default:
            break
        }
    }

    private func moveSelection(_ direction: ManageKeyboardCommand) {
        let accountIDs = accounts.map(\.id)
        selectedAccountID = nextSelectionID(currentID: selectedAccountID, accountIDs: accountIDs, direction: direction)
    }

    private func triggerSwitchSelected() {
        guard let selectedAccountID,
              let account = accounts.first(where: { $0.id == selectedAccountID })
        else {
            return
        }

        guard controller.statusSnapshot.canSwitch, !account.isActive else {
            return
        }

        controller.sendStatusCommand(.switchAccount(account.id))
    }

    private func syncSelection() {
        if let selectedAccountID,
           accounts.contains(where: { $0.id == selectedAccountID })
        {
            return
        }

        if let active = accounts.first(where: { $0.isActive }) {
            selectedAccountID = active.id
            return
        }

        selectedAccountID = accounts.first?.id
    }

    private func rowBackgroundColor(selected: Bool, hovered: Bool, enabled: Bool) -> Color {
        if enabled && hovered {
            return Color.accentColor.opacity(UITheme.Popover.hoverFillOpacity)
        }
        if selected {
            return Color.accentColor.opacity(UITheme.Popover.selectedFillOpacity)
        }
        return .clear
    }

    private func menuBackgroundColor(hovered: Bool, disabled: Bool) -> Color {
        if !disabled && hovered {
            return Color.accentColor.opacity(UITheme.Popover.hoverFillOpacity)
        }
        return .clear
    }

    private func menuForegroundColor(hovered: Bool, disabled: Bool) -> Color {
        if disabled {
            return .secondary
        }
        if hovered {
            return .white
        }
        return .primary
    }
}
