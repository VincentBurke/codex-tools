import SwiftUI

enum UITheme {
    enum Spacing {
        static let xxs: CGFloat = 3
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum CornerRadius {
        static let small: CGFloat = 5
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
    }

    enum Manage {
        static let rowMinHeight: CGFloat = 44
        static let metricColumnWidth: CGFloat = 56
        static let resetColumnWidth: CGFloat = 72
        static let statusColumnWidth: CGFloat = 92
        static let actionColumnWidth: CGFloat = 66
        static let disclosureColumnWidth: CGFloat = 14
        static let detailsLeadingInset: CGFloat = 32
    }

    enum Popover {
        static let width: CGFloat = 380
        static let rowHeight: CGFloat = 34
        static let maxListHeight: CGFloat = 240
        static let selectedFillOpacity: CGFloat = 0.16
        static let hoverFillOpacity: CGFloat = 0.28
    }

    enum Font {
        static let title = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular)
        static let bodyStrong = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular)
        static let captionStrong = SwiftUI.Font.system(size: 12, weight: .semibold)
    }

    enum Color {
        static let lowUsage = SwiftUI.Color(nsColor: .systemOrange)
        static let depletedUsage = SwiftUI.Color(nsColor: .systemRed)
        static let staleUsage = SwiftUI.Color(nsColor: .systemYellow)
        static let unavailableUsage = SwiftUI.Color(nsColor: .secondaryLabelColor)
    }
}
