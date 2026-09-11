import Foundation









enum TrayModel {

    enum Entry: Equatable, Identifiable, Sendable {
        case separator(position: Int)

        case info(id: UInt32, label: String)

        case action(Action)

        case section(Section)

        case account(Account)

        var id: String {
            switch self {
            case .separator(let position): "separator-\(position)"
            case .info(let id, _): "item-\(id)"
            case .action(let action): "item-\(action.id)"
            case .section(let section): "item-\(section.id)"
            case .account(let account): "item-\(account.id)"
            }
        }
    }

    struct Action: Equatable, Identifiable, Sendable {
        let id: UInt32
        let label: String
        let enabled: Bool
        let intent: Intent
        var isQuit: Bool { intent == .quit_app }
    }

    struct Section: Equatable, Identifiable, Sendable {
        let id: UInt32

        let header: String

        var entries: [Entry]
    }


    struct TitleSplit: Equatable, Sendable {
        let label: String
        let suffix: String
    }



    struct Account: Equatable, Identifiable, Sendable {
        let id: UInt32
        let accountID: String

        let title: String


        let split: TitleSplit?
        let enabled: Bool

        let isCursor: Bool
        let submenu: Submenu?
    }




    struct Submenu: Equatable, Sendable {

        let summary: String
        let usage: String
        let updated: String

        let refreshLabel: String
        let canRefresh: Bool
        let refresh: Intent

        let failover: Failover?

        let openLabel: String
        let open: Intent
    }

    enum Failover: Equatable, Sendable {

        case active(String)

        case switchable(String, Intent)

        case info(String)

        var label: String {
            switch self {
            case .active(let label), .info(let label), .switchable(let label, _): label
            }
        }
    }

    static let openAccountPrefix = "tray.open_account:"
    static let titleSeparator = " — "


    static func intent(for command: String) -> Intent? {
        switch command {
        case "tray.refresh_all": .refresh_all
        case "tray.open_details": .open_details
        case "tray.quit": .quit_app
        default:
            command.hasPrefix(openAccountPrefix) && command.count > openAccountPrefix.count
                ? .open_account(account_id: String(command.dropFirst(openAccountPrefix.count)))
                : nil
        }
    }

    static func entries(_ view: ViewState) -> [Entry] {
        var result: [Entry] = []
        var section: Section?
        var pendingSeparator: Int?
        let rows = Dictionary(view.rows.map { ($0.account_id, $0) }, uniquingKeysWith: { first, _ in first })

        func closeSection() {
            if let open = section {
                result.append(.section(open))
                section = nil
            }
        }

        for (position, item) in view.tray.items.enumerated() {
            if item.separator {
                pendingSeparator = position
                continue
            }


            let isHeader = item.command.isEmpty && !item.enabled && !item.label.isEmpty && view.tray_provider_headers.contains(item.label)
            if isHeader {

                closeSection()
                pendingSeparator = nil
                section = Section(id: item.id, header: item.label, entries: [])
                continue
            }
            if let position = pendingSeparator {
                pendingSeparator = nil
                if section != nil {
                    closeSection()
                } else {
                    result.append(.separator(position: position))
                }
            }
            let entry: Entry
            if let intent = intent(for: item.command) {
                if case .open_account(let accountID) = intent {
                    entry = .account(account(item, accountID: accountID, row: rows[accountID], tray: view.tray))
                } else {
                    entry = .action(Action(id: item.id, label: item.label, enabled: item.enabled, intent: intent))
                }
            } else {
                entry = .info(id: item.id, label: item.label)
            }
            if section != nil {
                section!.entries.append(entry)
            } else {
                result.append(entry)
            }
        }
        closeSection()
        return result
    }


    static func helpText(_ projection: Projection?) -> String? {
        projection?.view.tray.help_text
    }

    static func submenu(for row: AccountView, tray: Tray) -> Submenu {
        let failover: Failover?
        if row.tray_uses_proxy && !row.tray_failover_text.isEmpty {
            if row.tray_is_active {
                failover = .active(row.tray_failover_text)
            } else if row.tray_can_switch {
                failover = .switchable(row.tray_failover_text, .begin_failover_switch_id(account_id: row.account_id))
            } else {
                failover = .info(row.tray_failover_text)
            }
        } else {
            failover = nil
        }
        return Submenu(
            summary: row.tray_summary_line,
            usage: row.tray_usage_text,
            updated: row.tray_updated_text,
            refreshLabel: tray.refresh_usage_label,
            canRefresh: row.tray_can_refresh,
            refresh: .refresh_account_id(account_id: row.account_id),
            failover: failover,
            openLabel: tray.open_in_settings_label,
            open: .open_account(account_id: row.account_id)
        )
    }


    static func split(title: String, label: String) -> TitleSplit? {
        let prefix = label + titleSeparator
        guard !label.isEmpty, title.hasPrefix(prefix), title.count > prefix.count else { return nil }
        return TitleSplit(label: label, suffix: String(title.dropFirst(label.count)))
    }

    private static func account(_ item: TrayItem, accountID: String, row: AccountView?, tray: Tray) -> Account {
        Account(
            id: item.id,
            accountID: accountID,
            title: item.label,
            split: row.map { split(title: item.label, label: $0.label) } ?? nil,
            enabled: item.enabled,
            isCursor: row?.tray_is_active ?? false,
            submenu: row.map { submenu(for: $0, tray: tray) }
        )
    }



    static func flattened(_ entries: [Entry]) -> [Entry] {
        entries.flatMap { entry -> [Entry] in
            if case .section(let section) = entry { return section.entries }
            return [entry]
        }
    }
}
