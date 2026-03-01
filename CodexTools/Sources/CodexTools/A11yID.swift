enum A11yID {
    enum manage {
        static let addAccount = "manage.addAccount"
        static let refresh = "manage.refresh"
        static let emptyAdd = "manage.emptyAdd"
        static let usageWarning = "manage.usageWarning"

        static func row(_ accountID: String) -> String {
            "manage.row.\(accountID)"
        }

        static func rowSwitch(_ accountID: String) -> String {
            "manage.row.switch.\(accountID)"
        }

        static func rowDisclosure(_ accountID: String) -> String {
            "manage.row.disclosure.\(accountID)"
        }
    }

    enum popover {
        static let refresh = "popover.refresh"
        static let nextBestCard = "popover.nextBest.card"
        static let nextBestSwitch = "popover.nextBest.switch"
        static let nextBestUnavailable = "popover.nextBest.unavailable"
        static let manage = "popover.manage"
        static let closeCodex = "popover.closeCodex"
        static let quit = "popover.quit"

        static func row(_ accountID: String) -> String {
            "popover.row.\(accountID)"
        }
    }

    enum add {
        static let mode = "add.mode"
        static let path = "add.path"
        static let browse = "add.browse"
        static let oauthOpenBrowser = "add.oauth.openBrowser"
        static let oauthCopyLink = "add.oauth.copyLink"
        static let submit = "add.submit"
        static let cancel = "add.cancel"
    }
}
