import SwiftUI

struct PaletteDetailLayout<Sidebar: View, Detail: View, Metadata: View>: View {
    let listWidth: CGFloat
    let detailTitle: String
    let sidebar: Sidebar
    let detail: Detail
    let metadata: Metadata

    init(
        listWidth: CGFloat,
        detailTitle: String,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder metadata: () -> Metadata
    ) {
        self.listWidth = listWidth
        self.detailTitle = detailTitle
        self.sidebar = sidebar()
        self.detail = detail()
        self.metadata = metadata()
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: listWidth)

            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                Text(detailTitle)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Spacing.xl)
                    .padding(.horizontal, Theme.Spacing.xl)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, Theme.Spacing.xl)

                metadata
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
