import SwiftUI

/// About画面。更新チェックはメニューと共用のコントローラを使う。
/// アラートは常時表示のRootView側で出すため、ここではメッセージ表示のみ行う。
struct AboutView: View {
    @Bindable var controller: UpdateCheckController

    @Environment(\.locale) private var locale
    private var lang: String { locale.language.languageCode?.identifier ?? "" }
    private func t(_ key: String) -> String { L10n.string(key, language: lang) }

    init(controller: UpdateCheckController = UpdateCheckController()) {
        self.controller = controller
    }

    /// 確認中・インストール中の状態に応じたボタン文言。
    private var installButtonTitle: String {
        if controller.isInstalling { return t("a.installing") }
        if controller.isChecking { return t("a.checking") }
        return t("a.check")
    }

    private var toolVersions: [ToolVersion] {
        AppInfo.toolVersions.map { ToolVersion(binary: $0.binary, version: $0.version) }
    }

    /// 同梱の `assets/images/icon-tree-01.png` を縦50pxで表示する。
    /// 取得不可時のみフォールバックする。
    @ViewBuilder
    private var appIcon: some View {
        if let image = AppInfo.appIconImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 50)
        } else {
            Image(systemName: "tree")
                .appFont(.largeTitle)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {

                    VStack(alignment: .leading, spacing: 8) {
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
                        GlassCTAButton(
                            title: installButtonTitle,
                            disabled: controller.isChecking || controller.isInstalling
                        ) {
                            controller.checkForUpdate()
                        }
                        if !controller.message.isEmpty {
                            Text(controller.message)
                                .appFont(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(t("a.group.app")).appFont(.headline)
                }

                GroupBox {

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
            .padding()
        }
        .navigationTitle(t("a.navTitle"))
    }
}

private struct ToolVersion: Identifiable {
    let id = UUID()
    var binary: String
    var version: String
}


