import CodexToolsCore
import SwiftUI

struct ManageAccountsView: View {
    @ObservedObject var controller: AppController

    @State private var expandedRowState: [String: Bool] = [:]
    @State private var nameDrafts: [String: String] = [:]
    @State private var renamingAccountID: String?

    @FocusState private var renameFocusedAccountID: String?

    private var visibleAccounts: [ManageAccountItem] {
        controller.manageSnapshot.accounts
    }

    private var unavailableAccounts: [ManageAccountItem] {
        terminalUnavailableAccounts(in: visibleAccounts)
    }

    private var selectedAccountBinding: Binding<String?> {
        Binding(
            get: { controller.selectedManageAccountID },
            set: { controller.setSelectedManageAccountID($0) }
        )
    }

    private var allUsageUnknown: Bool {
        guard !visibleAccounts.isEmpty else {
            return false
        }

        return visibleAccounts.allSatisfy { account in
            account.availability == .unavailable
        }
    }

    var body: some View {
        content
            .frame(minWidth: 560, minHeight: 420)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        controller.presentAddAccountSheet()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    .help("Add account")
                    .accessibilityLabel("Add Account")
                    .accessibilityIdentifier(A11yID.manage.addAccount)

                    Button {
                        controller.sendStatusCommand(.refreshAll)
                    } label: {
                        if controller.statusSnapshot.isRefreshingUsage {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .help("Refresh usage")
                    .accessibilityLabel("Refresh Usage")
                    .disabled(controller.statusSnapshot.isRefreshingUsage)
                    .accessibilityIdentifier(A11yID.manage.refresh)
                }
            }
            .sheet(isPresented: $controller.isAddAccountSheetPresented) {
                AddAccountSheetView(
                    onSubmit: { controller.submitAddAccount(input: $0) },
                    onCancel: { controller.dismissAddAccountSheet() }
                )
            }
            .background(keyboardShortcuts)
            .onExitCommand {
                if collapseExpandedRows() {
                    return
                }
                if controller.isAddAccountSheetPresented {
                    controller.dismissAddAccountSheet()
                }
            }
            .onAppear {
                reconcileSelection()
                reconcileExpandedRows()
                syncNameDrafts()
            }
            .onChange(of: controller.manageSnapshot.accounts) { _, _ in
                reconcileSelection()
                reconcileExpandedRows()
                syncNameDrafts()
            }
    }

    @ViewBuilder
    private var content: some View {
        if visibleAccounts.isEmpty {
            ContentUnavailableView {
                Label("No accounts yet", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("Add an account to begin switching.")
            } actions: {
                Button("Add Account...") {
                    controller.presentAddAccountSheet()
                }
                .accessibilityIdentifier(A11yID.manage.emptyAdd)
            }
        } else {
            List(selection: selectedAccountBinding) {
                if !unavailableAccounts.isEmpty {
                    cleanupStrip(unavailableAccounts)
                        .listRowInsets(
                            EdgeInsets(
                                top: UITheme.Spacing.xs,
                                leading: UITheme.Spacing.m,
                                bottom: UITheme.Spacing.xs,
                                trailing: UITheme.Spacing.m
                            )
                        )
                        .accessibilityIdentifier(A11yID.manage.cleanupStrip)
                }

                if allUsageUnknown {
                    warningStrip("Usage unavailable; refresh to evaluate switch target.")
                        .listRowInsets(
                            EdgeInsets(
                                top: UITheme.Spacing.xs,
                                leading: UITheme.Spacing.m,
                                bottom: UITheme.Spacing.xs,
                                trailing: UITheme.Spacing.m
                            )
                        )
                        .accessibilityIdentifier(A11yID.manage.usageWarning)
                }

                ForEach(visibleAccounts, id: \.id) { account in
                    accountRow(account)
                        .tag(account.id)
                        .listRowInsets(
                            EdgeInsets(
                                top: UITheme.Spacing.xs,
                                leading: UITheme.Spacing.m,
                                bottom: UITheme.Spacing.xs,
                                trailing: UITheme.Spacing.m
                            )
                        )
                }
            }
            .listStyle(.plain)
        }
    }

    private func accountRow(_ account: ManageAccountItem) -> some View {
        let model = makeManageRowDisplayModel(account)
        let metrics = makeManageRowMetricPresentation(
            weeklyRemaining: account.weeklyRemaining,
            fiveHourRemaining: account.fiveHourRemaining
        )
        let health = healthIndicator(for: account)
        let expanded = expandedRowState[account.id] ?? false

        return VStack(alignment: .leading, spacing: UITheme.Spacing.xs) {
            HStack(spacing: UITheme.Spacing.s) {
                avatar(for: model)

                VStack(alignment: .leading, spacing: UITheme.Spacing.xxs) {
                    if renamingAccountID == account.id {
                        TextField("Account name", text: draftBinding(for: account))
                            .textFieldStyle(.roundedBorder)
                            .font(UITheme.Font.bodyStrong)
                            .focused($renameFocusedAccountID, equals: account.id)
                            .onSubmit {
                                commitRename(for: account)
                            }
                    } else {
                        Text(model.name)
                            .font(UITheme.Font.bodyStrong)
                            .lineLimit(1)
                    }

                    Text(rowSubtitle(for: account))
                        .font(UITheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: UITheme.Spacing.xs)

                usageMetric(label: "Weekly", value: metrics.weeklyText, color: remainingColor(account.weeklyRemaining))
                usageMetric(label: "5h", value: metrics.fiveHourText, color: remainingColor(account.fiveHourRemaining))
                weeklyResetSummary(account.weeklyResetCountdown)
                if account.isUsageRefreshing {
                    refreshingIndicator
                } else {
                    statusIndicator(health)
                }

                switchActionControl(for: account)

                Button {
                    toggleExpandedRow(account.id)
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: UITheme.Manage.disclosureColumnWidth, alignment: .trailing)
                .accessibilityIdentifier(A11yID.manage.rowDisclosure(account.id))
            }
            .frame(maxWidth: .infinity, minHeight: UITheme.Manage.rowMinHeight, alignment: .leading)

            if expanded {
                expandedRowContent(account)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                // Use a simultaneous single-tap recognizer so selection applies immediately
                // without waiting for the double-click recognizer to fail.
                controller.setSelectedManageAccountID(account.id)
            }
        )
        .onTapGesture(count: 2) {
            // Double-click toggles row details; single-click selection is handled above.
            toggleExpandedRow(account.id)
        }
        .contextMenu {
            Button("Rename") {
                beginInlineRename(for: account)
            }

            Button("Delete...", role: .destructive) {
                controller.setSelectedManageAccountID(account.id)
                controller.requestDelete(account)
            }

            Divider()

            Button("Refresh Usage") {
                refreshUsageFromContext(account.id)
            }
            .disabled(account.isUsageRefreshing)
        }
        .accessibilityIdentifier(A11yID.manage.row(account.id))
    }

    private func expandedRowContent(_ account: ManageAccountItem) -> some View {
        VStack(alignment: .leading, spacing: UITheme.Spacing.xxs) {
            Divider()

            metadataRow("Email", account.email ?? "--")
            metadataRow("Auth", account.authModeLabel)
            metadataRow("Plan", account.plan ?? "--")
            metadataRow("Last Used", account.lastUsed ?? "--")
            metadataRow("Account ID", account.id)
            metadataRow("5h Remaining", percentLabel(account.fiveHourRemaining), valueColor: remainingColor(account.fiveHourRemaining))
            metadataRow("Weekly Remaining", percentLabel(account.weeklyRemaining), valueColor: remainingColor(account.weeklyRemaining))
            metadataRow("Weekly Reset In", account.weeklyResetCountdown ?? "--", valueColor: resetCountdownColor(account.weeklyResetCountdown))
            metadataRow("Usage Refreshed", account.usageLastRefreshed ?? "--")
            metadataRow("Usage", usageDetailsLabel(for: account), valueColor: usageDetailsColor(for: account))

            if let usageError = normalizedUsageError(account.usageError) {
                metadataRow("Usage Error", usageError, valueColor: UITheme.Color.unavailableUsage, lineLimit: 2)
            }
        }
        .padding(.leading, UITheme.Manage.detailsLeadingInset)
        .padding(.bottom, UITheme.Spacing.xxs)
    }

    private func metadataRow(
        _ label: String,
        _ value: String,
        valueColor: Color = .primary,
        lineLimit: Int = 1
    ) -> some View {
        LabeledContent {
            Text(value)
                .font(UITheme.Font.body)
                .foregroundStyle(valueColor)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(label)
                .font(UITheme.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func warningStrip(_ message: String) -> some View {
        Label {
            Text(message)
                .font(UITheme.Font.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(UITheme.Color.lowUsage)
        }
        .padding(.vertical, UITheme.Spacing.xxs)
    }

    private func cleanupStrip(_ accounts: [ManageAccountItem]) -> some View {
        HStack(alignment: .center, spacing: UITheme.Spacing.s) {
            Label(
                accounts.count == 1 ? "1 unavailable account found." : "\(accounts.count) unavailable accounts found.",
                systemImage: "exclamationmark.octagon.fill"
            )
            .font(UITheme.Font.captionStrong)
            .foregroundStyle(UITheme.Color.depletedUsage)

            Spacer(minLength: UITheme.Spacing.xs)

            Button("Remove Unavailable Accounts...") {
                controller.requestDeleteUnavailable(accounts)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier(A11yID.manage.cleanupRemove)
        }
        .padding(.vertical, UITheme.Spacing.xxs)
    }

    private func usageMetric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(UITheme.Font.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(UITheme.Font.bodyStrong)
                .foregroundStyle(color)
        }
        .frame(width: UITheme.Manage.metricColumnWidth, alignment: .trailing)
    }

    private func weeklyResetSummary(_ countdown: String?) -> some View {
        HStack(spacing: UITheme.Spacing.xxs) {
            Image(systemName: "clock")
                .font(UITheme.Font.caption)
            Text(countdown ?? "--")
                .font(UITheme.Font.captionStrong)
        }
        .foregroundStyle(.secondary)
        .frame(width: UITheme.Manage.resetColumnWidth, alignment: .trailing)
        .help("Time until weekly reset")
    }

    private func statusIndicator(_ health: ManageRowHealthPresentation) -> some View {
        Label(health.label, systemImage: health.symbolName)
            .font(UITheme.Font.captionStrong)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(statusColor(for: health.effectiveSeverity))
            .frame(width: UITheme.Manage.statusColumnWidth, alignment: .trailing)
            .help("Overall account health")
    }

    private var refreshingIndicator: some View {
        HStack(spacing: UITheme.Spacing.xxs) {
            ProgressView()
                .controlSize(.small)
            Text("Refreshing")
                .font(UITheme.Font.captionStrong)
        }
        .foregroundStyle(.secondary)
        .frame(width: UITheme.Manage.statusColumnWidth, alignment: .trailing)
        .help("Usage refresh in progress")
    }

    private func switchActionControl(for account: ManageAccountItem) -> some View {
        let presentation = makeManageRowActionPresentation(account: account, canSwitch: controller.manageSnapshot.canSwitch)

        return Group {
            switch presentation.kind {
            case .active:
                Text(presentation.label)
                    .font(UITheme.Font.captionStrong)
                    .foregroundStyle(.tint)
            case .switchAccount:
                Button(presentation.label) {
                    controller.setSelectedManageAccountID(account.id)
                    controller.sendManageAction(.switch(account.id))
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(!presentation.isEnabled)
                .accessibilityIdentifier(A11yID.manage.rowSwitch(account.id))
            case .remove:
                Button(presentation.label, role: .destructive) {
                    controller.setSelectedManageAccountID(account.id)
                    controller.requestDelete(account)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(A11yID.manage.rowRemove(account.id))
            }
        }
        .frame(width: UITheme.Manage.actionColumnWidth, alignment: .trailing)
    }

    private func statusColor(for severity: UsageSeverity) -> Color {
        switch severity {
        case .healthy:
            return .green
        case .low:
            return UITheme.Color.lowUsage
        case .depleted:
            return UITheme.Color.depletedUsage
        case .stale:
            return UITheme.Color.staleUsage
        case .paymentRequired, .expired, .disabled:
            return UITheme.Color.depletedUsage
        case .unavailable:
            return UITheme.Color.unavailableUsage
        }
    }

    private func resetCountdownColor(_ countdown: String?) -> Color {
        guard let hours = parseResetHours(from: countdown) else {
            return .secondary
        }

        switch hours {
        case ...6:
            return .green
        case ...24:
            return UITheme.Color.lowUsage
        case ...72:
            return .orange
        default:
            return .secondary
        }
    }

    private func parseResetHours(from countdown: String?) -> Int? {
        guard let countdown else {
            return nil
        }

        let trimmed = countdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "--" else {
            return nil
        }

        var days = 0
        var hours = 0
        var found = false

        for part in trimmed.split(separator: " ") {
            if part.hasSuffix("d"), let value = Int(part.dropLast()) {
                days = value
                found = true
            } else if part.hasSuffix("h"), let value = Int(part.dropLast()) {
                hours = value
                found = true
            }
        }

        guard found else {
            return nil
        }

        return (days * 24) + hours
    }

    private func rowSubtitle(for account: ManageAccountItem) -> String {
        makeManageRowSubtitle(
            plan: account.plan,
            availability: account.availability
        )
    }

    private func healthIndicator(for account: ManageAccountItem) -> ManageRowHealthPresentation {
        makeManageRowHealthPresentation(
            availability: account.availability,
            weeklyRemaining: account.weeklyRemaining,
            fiveHourRemaining: account.fiveHourRemaining
        )
    }

    private func remainingColor(_ value: UInt8?) -> Color {
        guard let value else {
            return UITheme.Color.unavailableUsage
        }

        switch value {
        case ..<3:
            return UITheme.Color.depletedUsage
        case 3..<30:
            return UITheme.Color.staleUsage
        default:
            return .green
        }
    }

    private func usageDetailsLabel(for account: ManageAccountItem) -> String {
        switch account.availability {
        case .paymentRequired:
            return "Payment Required"
        case .expired:
            return "Expired"
        case .disabled:
            return "Disabled"
        case .unavailable:
            return "Unavailable"
        case .stale:
            return "Stale"
        case .fresh:
            return "Fresh"
        }
    }

    private func usageDetailsColor(for account: ManageAccountItem) -> Color {
        switch account.availability {
        case .paymentRequired, .expired, .disabled:
            return UITheme.Color.depletedUsage
        case .unavailable:
            return UITheme.Color.unavailableUsage
        case .stale:
            return UITheme.Color.staleUsage
        case .fresh:
            return .secondary
        }
    }

    private func avatar(for model: AccountRowDisplayModel) -> some View {
        let initial = model.name.first(where: { $0.isLetter || $0.isNumber }).map {
            String($0).uppercased()
        } ?? "?"

        return ZStack {
            Circle()
                .fill(model.isActive ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.30))

            Text(initial)
                .font(UITheme.Font.captionStrong)
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
    }

    private var keyboardShortcuts: some View {
        HStack(spacing: 0) {
            keyboardShortcut(.return, command: .switchSelected)
            keyboardShortcut(.delete, command: .deleteSelected)
            keyboardShortcut(.space, command: .toggleExpanded)
        }
        .frame(width: 0, height: 0)
        .opacity(0.001)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func keyboardShortcut(
        _ key: KeyEquivalent,
        modifiers: EventModifiers = [],
        command: ManageKeyboardCommand
    ) -> some View {
        Button("") {
            handleKeyboard(command)
        }
        .keyboardShortcut(key, modifiers: modifiers)
    }

    private func handleKeyboard(_ command: ManageKeyboardCommand) {
        if renameFocusedAccountID != nil {
            return
        }

        let resolution = resolveManageKeyboardCommand(
            command,
            visibleAccounts: visibleAccounts,
            selectedAccountID: controller.selectedManageAccountID,
            canSwitch: controller.manageSnapshot.canSwitch
        )

        switch resolution {
        case .none:
            return
        case .select(let nextID):
            controller.setSelectedManageAccountID(nextID)
        case .switchAccount(let id):
            controller.sendManageAction(.switch(id))
        case .requestDelete(let id):
            guard let account = visibleAccounts.first(where: { $0.id == id }) else {
                return
            }
            controller.requestDelete(account)
        case .presentAddAccount:
            controller.presentAddAccountSheet()
        case .toggleExpanded(let id):
            toggleExpandedRow(id)
        }
    }

    private func toggleExpandedRow(_ accountID: String) {
        controller.setSelectedManageAccountID(accountID)
        let expanded = expandedRowState[accountID] ?? false
        expandedRowState[accountID] = !expanded
    }

    private func collapseExpandedRows() -> Bool {
        if expandedRowState.values.contains(true) {
            expandedRowState.removeAll()
            renamingAccountID = nil
            renameFocusedAccountID = nil
            return true
        }
        return false
    }

    private func reconcileSelection() {
        controller.setSelectedManageAccountID(
            reconcileSelectionID(
                currentID: controller.selectedManageAccountID,
                accounts: visibleAccounts,
                id: \.id,
                isActive: \.isActive
            )
        )
    }

    private func reconcileExpandedRows() {
        let validIDs = Set(visibleAccounts.map(\.id))
        expandedRowState = expandedRowState.filter { validIDs.contains($0.key) }
        nameDrafts = nameDrafts.filter { validIDs.contains($0.key) }

        guard let renamingAccountID else {
            return
        }

        if !validIDs.contains(renamingAccountID) {
            self.renamingAccountID = nil
            renameFocusedAccountID = nil
        }
    }

    private func syncNameDrafts() {
        let validIDs = Set(visibleAccounts.map(\.id))
        nameDrafts = nameDrafts.filter { validIDs.contains($0.key) }

        for account in visibleAccounts {
            if renamingAccountID == account.id {
                continue
            }
            nameDrafts[account.id] = account.name
        }
    }

    private func draftBinding(for account: ManageAccountItem) -> Binding<String> {
        Binding(
            get: { nameDrafts[account.id] ?? account.name },
            set: { nameDrafts[account.id] = $0 }
        )
    }

    private func beginInlineRename(for account: ManageAccountItem) {
        controller.setSelectedManageAccountID(account.id)
        nameDrafts[account.id] = account.name
        renamingAccountID = account.id

        DispatchQueue.main.async {
            renameFocusedAccountID = account.id
        }
    }

    private func commitRename(for account: ManageAccountItem) {
        let draft = (nameDrafts[account.id] ?? account.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        renamingAccountID = nil
        renameFocusedAccountID = nil

        guard !draft.isEmpty else {
            nameDrafts[account.id] = account.name
            return
        }
        guard draft != account.name else {
            nameDrafts[account.id] = account.name
            return
        }

        controller.sendManageAction(.renameInline(id: account.id, newName: draft))
    }

    private func refreshUsageFromContext(_ accountID: String) {
        controller.setSelectedManageAccountID(accountID)
        controller.sendManageAction(.refreshUsage(accountID))
    }
}
