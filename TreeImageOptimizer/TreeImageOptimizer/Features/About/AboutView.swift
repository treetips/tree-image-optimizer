import SwiftUI

/// About画面。更新チェックはメニューと共用のコントローラを使う。
/// アラートは常時表示のRootView側で出すため、ここではメッセージ表示のみ行う。
struct AboutView: View {
    @Bindable var controller: UpdateCheckController
    let toolsUpdate: ToolsUpdateController?
    let updatesEnabled: Bool

    @Environment(\.locale) private var locale
    private var lang: String { locale.language.languageCode?.identifier ?? "" }
    private func t(_ key: String) -> String { L10n.string(key, language: lang) }

    init(
        controller: UpdateCheckController = UpdateCheckController(),
        toolsUpdate: ToolsUpdateController? = nil,
        updatesEnabled: Bool = true
    ) {
        self.controller = controller
        self.toolsUpdate = toolsUpdate
        self.updatesEnabled = updatesEnabled
    }

    private var updatePresentation: AboutUpdatePresentation {
        AboutUpdatePresentation(
            controller: controller,
            toolsUpdate: toolsUpdate,
            language: lang,
            updatesEnabled: updatesEnabled
        )
    }

    private var toolVersions: [ToolVersion] {
        AppInfo.toolVersions.map { ToolVersion(binary: $0.binary, version: $0.version) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                applicationCard
                updateCard
                versionsCard
            }
            .padding()
        }
        .navigationTitle(t("a.navTitle"))
    }

    private var updateCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                updateColumns

                if let detailMessage = updatePresentation.detailMessage {
                    Text(detailMessage)
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                updateButton
            }
            .padding(.vertical, 4)
        } label: {
            Text(t("a.group.updates")).appFont(.headline)
        }
    }

    private var updateColumns: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                updateColumn(title: t("a.update.app"), status: updatePresentation.appStatus)
                updateColumn(title: t("a.update.libraries"), status: updatePresentation.toolsStatus)
            }
            VStack(alignment: .leading, spacing: 16) {
                updateColumn(title: t("a.update.app"), status: updatePresentation.appStatus)
                updateColumn(title: t("a.update.libraries"), status: updatePresentation.toolsStatus)
            }
        }
    }

    private func updateColumn(title: String, status: AboutUpdateStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).appFont(.headline)
            AboutUpdateStatusBadge(status: status)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var applicationCard: some View {
        GlassCard {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    appIcon
                    Text("Tree Image Optimizer")
                        .appFont(.title2)
                }
                GridRow {
                    Text(t("a.version")).appFont(.headline)
                    Text(AppInfo.bundleVersion).appFont(.body)
                }
                GridRow {
                    Text("GitHub").appFont(.headline)
                    Link(destination: AppInfo.githubURL) {
                        Text(AppInfo.githubURL.absoluteString).appFont(.footnote)
                    }
                }
                GridRow {
                    Text("Copyright").appFont(.headline)
                    Text("Copyright @2026 treetips555")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Text(t("a.group.app")).appFont(.headline)
        }
    }

    private var versionsCard: some View {
        GlassCard {
            // Tableは内容量に関わらずスクロールバーを出すため、
            // 全行が収まるGridで表示する（フェーズ2 UIレビュー反映）。
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text(t("a.col.binary")).appFont(.headline).bold()
                    Text(t("a.col.version")).appFont(.headline).bold()
                }
                Divider()
                ForEach(toolVersions) { tool in
                    GridRow {
                        Text(tool.binary).appFont(.body)
                        Text(tool.version).appFont(.body)
                    }
                    Divider()
                }
            }
            .padding(.vertical, 4)
        } label: {
            Text(t("a.group.versions")).appFont(.headline)
        }
    }

    /// 同梱の `assets/images/icon-tree-01.png` を縦50pxで表示する。
    /// 取得不可時のみフォールバックする。
    @ViewBuilder
    private var appIcon: some View {
        if let image = AppInfo.appIconImage {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(height: 50)
        } else {
            Image(systemName: "tree")
                .appFont(.largeTitle)
        }
    }

    private var updateButton: some View {
        GlassCTAButton(
            title: updatePresentation.primaryButtonTitle,
            disabled: !updatePresentation.primaryButtonEnabled,
            tint: updatePresentation.primaryButtonTint
        ) {
            updatePresentation.performPrimaryAction()
        }
    }
}

private struct ToolVersion: Identifiable {
    let id = UUID()
    var binary: String
    var version: String
}
