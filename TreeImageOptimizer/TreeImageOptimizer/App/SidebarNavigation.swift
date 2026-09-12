import Foundation

/// 左サイドナビの選択状態。App層で生成し、`RootView` とメニューコマンドで共用する。
@Observable
@MainActor
final class SidebarNavigation {
    var selection: SidebarSelection = .convert
}
