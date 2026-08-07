import AppKit
import SwiftUI

/// Central design tokens for the palette UI (dark design system per `docs/ui.md`).
enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 20
        static let feedbackToastHorizontal: CGFloat = 8
        static let feedbackToastVertical: CGFloat = 8
        static let rowVertical: CGFloat = 7
        /// Calculator answer card's roomier vertical breathing room.
        static let xxxl: CGFloat = 28
        /// Gap under a category header before its first row; shared by every palette list's `SectionHeader`.
        static let sectionHeaderBottom: CGFloat = 4
        /// Space above a category header (every header except the list's first), which reads as bottom padding closing the previous section — shared by every palette list.
        static let sectionSpacing: CGFloat = 12
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        static let menu: CGFloat = 6
        /// Hover highlight behind a popover menu row.
        static let menuRow: CGFloat = 10
        static let menuPanel: CGFloat = 16
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 10
        static let keyCap: CGFloat = 6
        static let checkbox: CGFloat = 4
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 4
    }

    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 475
        /// Fraction of the active screen's visible height between the top of the visible area and the palette's top edge; the window grows downward from this edge (Spotlight-style upper placement).
        static let paletteTopMarginFraction: CGFloat = 0.18
        static let headerHeight: CGFloat = 44
        /// Fixed slot for the header leading glyph (search / back chevron / mode icon) so the search field starts at the same x in every mode — glyphs have different intrinsic widths (chevron 14, magnifyingglass 22). Sized to the magnifyingglass so the launcher spacing is unchanged.
        static let headerIconSlot: CGFloat = 28
        /// Vertical breathing room above the search row — constant across compact/expanded so the bar never shifts when typing flips the state; also the compact bar's symmetric top/bottom slack.
        static let headerPadding: CGFloat = 10
        static let searchFieldPointSize: CGFloat = 18
        static let inlineArgumentHeight: CGFloat = 28
        static let inlineArgumentMinimumWidth: CGFloat = 72
        static let inlineArgumentHelpBadge: CGFloat = 14
        /// Collapsed compact bar: the search row centered in symmetric `headerPadding` slack.
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        static let bottomBarHeight: CGFloat = 52
        static let rowIcon: CGFloat = 24
        static let checkbox: CGFloat = 16
        static let keyCap: CGFloat = 18
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 16
        static let menuButton: CGFloat = 36
        static let feedbackHalo: CGFloat = 18
        static let feedbackToastMaxWidth: CGFloat = 420
        static let feedbackToastBottomInset: CGFloat = 48
        /// Minimum height for each value column so badges sit near the card's lower edge.
        static let calcCardColumnHeight: CGFloat = 88
        static let clipboardListWidth: CGFloat = 290
        static let emojiCell: CGFloat = 56
        static let menuWidth: CGFloat = 276
        /// Square slot for a popover-menu row's leading glyph. 20 (not the 16 the artwork suggests) because an `IconCache` app icon only paints ~85% of its canvas: at 20 its visible artwork is 17pt, matching the 17–18pt a `.body` SF Symbol renders at, so symbol and app-icon rows read the same size.
        static let menuIcon: CGFloat = 20
        static let statusDot: CGFloat = 6
    }

    /// System text styles (not hardcoded sizes) so the UI honors Dynamic Type.
    enum Typography {
        static let searchField = Font.system(size: Theme.Size.searchFieldPointSize, weight: .regular)
        static let headerIcon = Font.system(size: 20, weight: .medium)
        static let rowTitle = Font.body
        static let body = Font.body
        static let bodyMedium = Font.body.weight(.medium)
        static let bodySemibold = Font.body.weight(.semibold)
        static let callout = Font.callout
        static let calloutMedium = Font.callout.weight(.medium)
        static let calloutSemibold = Font.callout.weight(.semibold)
        static let caption = Font.caption
        static let captionMonospacedDigit = Font.caption.monospacedDigit()
        static let captionMedium = Font.caption.weight(.medium)
        static let captionSemibold = Font.caption.weight(.semibold)
        static let caption2 = Font.caption2
        static let caption2Medium = Font.caption2.weight(.medium)
        static let caption2Semibold = Font.caption2.weight(.semibold)
        static let headline = Font.headline
        static let headlineSemibold = Font.headline.weight(.semibold)
        static let subheadline = Font.subheadline
        static let titleBold = Font.title.weight(.bold)
        static let title2Bold = Font.title2.weight(.bold)
        static let title3 = Font.title3
        static let title3Semibold = Font.title3.weight(.semibold)
        static let largeTitle = Font.largeTitle
        static let iconMicro = Font.system(size: 7, weight: .semibold)
        static let iconClose = Font.system(size: 9, weight: .semibold)
        static let iconTiny = Font.system(size: 10)
        static let iconSmall = Font.system(size: 12)
        static let iconMedium = Font.system(size: 13, weight: .medium)
        static let iconMediumSmall = Font.system(size: 14, weight: .medium)
        static let iconLarge = Font.system(size: 18, weight: .medium)
        static let iconLargeSemibold = Font.system(size: 16, weight: .semibold)
        static let iconXL = Font.system(size: 22, weight: .medium)
        static let iconHero = Font.system(size: 30, weight: .semibold)
        static let emojiGlyph = Font.system(size: 30)
        static let emptyStateIcon = Font.system(size: 26, weight: .medium)
        static let largeTitleIcon = Font.system(.largeTitle)
        static let monospacedSubheadline = Font.system(.subheadline, design: .monospaced)
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.subheadline.weight(.medium)
        /// The big value line on the calculator answer card (both source and target sides).
        static let calcResult = Font.largeTitle
        static let calcBadge = Font.subheadline.weight(.semibold)
        static let calcArrow = Font.callout.weight(.semibold)
        static let keyCap = Font.caption
        static let bar = Font.callout.weight(.medium)
        static let feedbackToast = Font.callout.weight(.medium)
        static let feedbackToastTitle = Font.callout.weight(.medium)
        static let menuRow = Font.body
        static let menuShortcut = Font.callout
        static let menuIcon = Font.body
        static let featureIcon = Font.system(size: 14, weight: .medium)
        static let featureEmoji = Font.system(size: 16)
    }

    enum Settings {
        enum Size {
            static let window = CGSize(width: 860, height: 620)
            static let sidebarWidth: CGFloat = 184
            static let sidebarIcon: CGFloat = 20
            static let sidebarRowHeight: CGFloat = 38
            static let sidebarSelectionHeight: CGFloat = 18
            static let searchHeight: CGFloat = 32
            static let controlHeight: CGFloat = 32
            static let headerIcon: CGFloat = 38
            static let controlIcon: CGFloat = 28
            static let searchResultIcon: CGFloat = 30
            static let statusIcon: CGFloat = 34
            static let modeTileHeight: CGFloat = 92
            static let modePreviewWidth: CGFloat = 74
            static let modePreviewHeight: CGFloat = 42
            static let compactModePreviewHeight: CGFloat = 18
            static let excludedAppChipMinimum: CGFloat = 150
            static let excludedAppChipHeight: CGFloat = 36
            static let applicationIcon: CGFloat = 22
            static let applicationPickerHeight: CGFloat = 320
            static let skinToneButton: CGFloat = 40
            static let shortcutColumn: CGFloat = 132
            static let visibilityButton: CGFloat = 36
            static let shortcutRecorderHeight: CGFloat = 28
            static let shortcutRecorderWidth: CGFloat = 102
            static let shortcutRecorderClearWidth: CGFloat = 26
            static let shortcutPopoverWidth: CGFloat = 280
            static let shortcutPopoverBodyHeight: CGFloat = 113
            static let shortcutPopoverFooterHeight: CGFloat = 36
            static let shortcutPopoverKeycap: CGFloat = 28
            static let aboutIcon: CGFloat = 88
            static let aboutGlow: CGFloat = 116
            static let aboutLinkTile: CGFloat = 116
        }

        enum Radius {
            static let navigation: CGFloat = Theme.Radius.row
            static let search: CGFloat = Theme.Radius.row
            static let iconTile: CGFloat = 7
            static let headerIcon: CGFloat = 10
            static let controlIcon: CGFloat = 8
            static let surface: CGFloat = Theme.Radius.card
            static let rowHighlight: CGFloat = 11
            static let modeTile: CGFloat = 12
            static let modePreview: CGFloat = 8
        }

        enum Layout {
            static let paneInset: CGFloat = 28
            static let sectionSpacing: CGFloat = 24
            static let sidebarInset: CGFloat = 10
            static let sidebarTopInset: CGFloat = 16
            static let groupSpacing: CGFloat = 22
            static let rowHorizontal: CGFloat = 16
            static let rowVertical: CGFloat = 12
            static let rowGap: CGFloat = 12
        }

        enum Colors {
            static let navigationSelection = Theme.Colors.selection
            static let navigationHover = Theme.Colors.rowHover
            static let searchFill = Theme.Colors.cardFill
            static let searchStroke = Theme.Colors.cardStroke
            static let searchFocus = Theme.Colors.border
            static let captureConflict = Color(red: 1.0, green: 0.36, blue: 0.46)
            static let captureConflictFill = captureConflict.opacity(0.08)
            static let captureSuccessFill = Color.green.opacity(0.07)
            static let sidebarSeparator = Theme.Colors.separator
            static let sidebarDimming = Theme.Colors.surfaceBase.opacity(0.10)
            static let surfaceFill = Theme.Colors.cardFill
            static let surfaceStroke = Theme.Colors.cardStroke
            static let rowDivider = Theme.Colors.separator
        }

        enum Motion {
            static let highlightFade = 0.10
        }
    }

    enum Colors {
        static let surfaceBase = Color(nsColor: .textBackgroundColor)
        static let contentBase = Color(nsColor: .textColor)
        static let panelSurface = Color(
            nsColor: NSColor(name: "OpencastPanelSurface") { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark
                    ? NSColor(calibratedWhite: 0.075, alpha: 0.96)
                    : NSColor(calibratedWhite: 0.96, alpha: 0.92)
            }
        )
        static let panelStroke = contentBase.opacity(0.08)
        static let footerSurface = Color(
            nsColor: NSColor(name: "OpencastFooterSurface") { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark
                    ? NSColor(calibratedWhite: 0.16, alpha: 0.96)
                    : NSColor(calibratedWhite: 0.99, alpha: 0.90)
            }
        )
        static let menuSurface = Color(
            nsColor: NSColor(name: "OpencastMenuSurface") { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark
                    ? NSColor(calibratedWhite: 0.16, alpha: 1)
                    : NSColor(calibratedWhite: 0.99, alpha: 1)
            }
        )
        static let footerStroke = contentBase.opacity(0.16)
        static let textPrimary = contentBase
        static let textOnPrimary = surfaceBase
        static let searchPlaceholder = contentBase.opacity(0.32)
        /// Selection fill: a soft neutral translucent layer shared by launcher and clipboard so both lists look identical.
        static let selection = contentBase.opacity(0.12)
        /// Mouse hover — a fainter layer that follows the cursor, visually distinct from selection.
        static let rowHover = contentBase.opacity(0.05)
        static let menuHover = contentBase.opacity(0.10)
        static let separator = contentBase.opacity(0.10)
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = contentBase.opacity(0.14)
        /// Control borders: outlined kbd chips.
        static let border = contentBase.opacity(0.20)
        static let textSecondary = contentBase.opacity(0.60)
        static let textTertiary = contentBase.opacity(0.40)
        static let rowSecondary = contentBase.opacity(0.56)
        static let rowKind = contentBase.opacity(0.52)
        static let sectionHeader = contentBase.opacity(0.58)
        /// Settings grouped "card": a faint raised surface whose hairline border doubles as the inset row divider.
        static let cardFill = contentBase.opacity(0.05)
        static let cardStroke = contentBase.opacity(0.10)
        /// Appearance-aware tint layered into the Liquid Glass floating controls.
        static let glassFrost = contentBase.opacity(0.10)
        static let feedbackFill = Color.green.opacity(0.18)
        static let feedbackShade = surfaceBase.opacity(0.40)
        static let feedbackStroke = contentBase.opacity(0.20)
        static let feedbackAccent = Color(red: 0.24, green: 0.82, blue: 0.52)
        static let success = Color.green
        static let warning = Color.orange
        static let attention = Color.yellow
        static let destructive = Color.red
        static let imagePlaceholder = contentBase.opacity(0.06)
        static let overlayDimming = surfaceBase.opacity(0.38)
        static let invisibleOverlay = Color.black.opacity(0.001)
        static let tooltipSurface = surfaceBase.opacity(0.86)
        static let onboardingGradientStart = contentBase.opacity(0.04)
        static let previewDimming = surfaceBase.opacity(0.38)
        static let previewSelected = contentBase.opacity(0.45)
        static let previewUnselected = contentBase.opacity(0.22)
        /// The violet of the app mark. The one non-white hue in the system, used only to tint the About support callout.
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)
        static let featureIconTileOpacity: CGFloat = 0.20
        static let generalAccent = contentBase.opacity(0.72)
        static let launcherAccent = Color(red: 0.42, green: 0.65, blue: 1.0)
        static let clipboardAccent = Color(red: 1.0, green: 0.62, blue: 0.32)
        static let emojiAccent = Color(red: 1.0, green: 0.76, blue: 0.30)
        static let calculatorAccent = Color(red: 0.42, green: 0.82, blue: 0.58)
        static let systemAccent = Color(red: 0.62, green: 0.68, blue: 0.80)
    }
}

struct FeatureIcon: View {
    private let systemImage: String?
    private let emoji: String?
    let tint: Color
    var size: CGFloat = Theme.Size.rowIcon

    init(systemImage: String, tint: Color, size: CGFloat = Theme.Size.rowIcon) {
        self.systemImage = systemImage
        self.emoji = nil
        self.tint = tint
        self.size = size
    }

    init(emoji: String, tint: Color, size: CGFloat = Theme.Size.rowIcon) {
        self.systemImage = nil
        self.emoji = emoji
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.featureIcon)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
            } else if let emoji {
                Text(emoji)
                    .font(Theme.Typography.featureEmoji)
            }
        }
        .frame(width: size, height: size)
        .background {
            let shape = RoundedRectangle(
                cornerRadius: Theme.Settings.Radius.iconTile,
                style: .continuous
            )
            shape
                .fill(Color.clear)
                .featureIconSurface(in: shape, tint: tint)
        }
    }
}

struct CommandIcon: View {
    let systemImage: String
    var tint: Color = Theme.Colors.textPrimary
    var size: CGFloat = Theme.Size.rowIcon

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: Theme.Settings.Radius.iconTile,
            style: .continuous
        )
        Image(systemName: systemImage)
            .font(Theme.Typography.featureIcon)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(shape.fill(Theme.Colors.controlSurface.opacity(0.56)))
            .overlay(shape.strokeBorder(Theme.Colors.border.opacity(0.72), lineWidth: 1))
    }
}

/// A single keycap chip: `.outline` for hotkey hints on rows, `.filled` for footer shortcuts.
struct KeyCapChip: View {
    enum Style {
        case outline
        case filled
    }

    let text: String
    var style: Style = .filled

    /// "↵" is absent from SF Pro and falls back to Lucida Grande UI, which seats it 1.1pt higher in the line box than the SF caps — visibly top-heavy in a chip. Nudging via `offset` is render-only, so the chip keeps the same footprint as every other cap.
    private static let returnGlyphDrop: CGFloat = 1.1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
        Text(text)
            .font(Theme.Typography.keyCap)
            .foregroundStyle(Theme.Colors.textSecondary)
            .offset(y: text == "↵" ? Self.returnGlyphDrop : 0)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minWidth: Theme.Size.keyCap, minHeight: Theme.Size.keyCap)
            .background {
                switch style {
                case .filled: shape.fill(Theme.Colors.controlSurface)
                case .outline: shape.strokeBorder(Theme.Colors.border, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// A floating Liquid Glass control surface on Tahoe, with an opaque fallback on older supported systems.
    @ViewBuilder
    func frosted<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive().tint(Theme.Colors.glassFrost), in: shape)
                .tint(.clear)
        } else {
            background(shape.fill(Theme.Colors.menuSurface))
                .overlay(shape.stroke(Theme.Colors.border, lineWidth: 1))
                .tint(.clear)
        }
    }

    @ViewBuilder
    func featureIconSurface<S: Shape>(in shape: S, tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                .regular.tint(tint.opacity(Theme.Colors.featureIconTileOpacity)),
                in: shape
            )
            .tint(.clear)
        } else {
            background(shape.fill(tint.opacity(Theme.Colors.featureIconTileOpacity)))
                .overlay(shape.stroke(Theme.Colors.border, lineWidth: 1))
        }
    }
}
