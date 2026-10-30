import SwiftUI

struct SourceSettingsPage: View {
    @ObservedObject var model: AppModel
    @State private var page = 0
    private let pageSize = 5

    private var pagination: SettingsPagination {
        SettingsPagination(count: model.settings.sources.count, pageSize: pageSize, requestedPage: page)
    }

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "应用扫描目录") {
                VStack(spacing: 0) {
                    ForEach(Array(model.settings.sources[pagination.range])) { source in
                        HStack(spacing: 10) {
                            Image(systemName: source.custom ? "folder.badge.plus" : "folder")
                                .foregroundStyle(Color.accentColor).frame(width: 20)
                            Text(displayPath(source.path))
                                .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                .help(source.path)
                            Spacer(minLength: 0)
                            if source.custom {
                                Button { model.removeSource(source.id) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                                    .help("仅移除扫描目录，不会删除文件夹")
                                    .accessibilityLabel("移除 \(displayPath(source.path))")
                            }
                            Toggle("扫描 \(displayPath(source.path))", isOn: enabledBinding(source))
                                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }
                        .frame(height: 46)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: CGFloat(pageSize) * 46)
                Divider()
                SettingsPager(pagination: pagination, page: $page, unit: "个目录")
            }
            HStack(spacing: 10) {
                Button("添加文件夹…") { model.addSource() }
                Spacer()
                Button(model.isScanning ? "正在扫描…" : "重新扫描") { model.rescan() }
                    .disabled(model.isScanning)
                Button("导入系统顺序") { model.importSystemLayout() }
                    .help("导入系统启动台的应用排列顺序")
            }
            SettingsHint(text: "关闭或移除来源仅影响应用扫描，不会删除磁盘上的文件。")
        }
        .onChange(of: model.settings.sources.count) { _, _ in page = pagination.page }
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private func enabledBinding(_ source: AppSource) -> Binding<Bool> {
        Binding {
            model.settings.sources.first(where: { $0.id == source.id })?.enabled ?? false
        } set: { enabled in
            guard let index = model.settings.sources.firstIndex(where: { $0.id == source.id }) else { return }
            model.settings.sources[index].enabled = enabled
        }
    }
}

struct HiddenAppsSettingsPage: View {
    @ObservedObject var model: AppModel
    @State private var page = 0
    @State private var query = ""
    private let pageSize = 4

    private var hidden: [AppItem] { model.apps.filter(\.hidden) }
    private var filtered: [AppItem] {
        hidden.filter { query.isEmpty || $0.effectiveName.localizedCaseInsensitiveContains(query) }
            .sorted { $0.effectiveName.localizedCaseInsensitiveCompare($1.effectiveName) == .orderedAscending }
    }
    private var pagination: SettingsPagination {
        SettingsPagination(count: filtered.count, pageSize: pageSize, requestedPage: page)
    }

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "已隐藏的应用") {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索隐藏应用", text: $query).textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                VStack(spacing: 0) {
                    if filtered.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: hidden.isEmpty ? "eye" : "magnifyingglass")
                                .font(.system(size: 25)).foregroundStyle(.tertiary)
                            Text(hidden.isEmpty ? "没有隐藏的应用" : "没有匹配的应用")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach(Array(filtered[pagination.range])) { app in
                            HStack(spacing: 10) {
                                Image(nsImage: model.icon(for: app)).resizable().frame(width: 28, height: 28)
                                Text(app.effectiveName).font(.system(size: 12)).lineLimit(1)
                                    .help(app.effectiveName)
                                Spacer(minLength: 8)
                                Button("取消隐藏") { model.unhide(app.id) }
                                    .controlSize(.small)
                                    .accessibilityLabel("取消隐藏 \(app.effectiveName)")
                            }
                            .frame(height: 42)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: CGFloat(pageSize) * 42)
                Divider()
                SettingsPager(pagination: pagination, page: $page, unit: "个应用")
            }
            SettingsCard(title: "搜索行为") {
                SettingsToggle(title: "搜索时包含隐藏应用", isOn: $model.settings.showHiddenInSearch)
            }
        }
        .onChange(of: query) { _, _ in page = 0 }
        .onChange(of: filtered.count) { _, _ in page = pagination.page }
    }
}

private struct SettingsPager: View {
    let pagination: SettingsPagination
    @Binding var page: Int
    let unit: String

    var body: some View {
        HStack(spacing: 10) {
            Text("共 \(pagination.count) \(unit)").foregroundStyle(.secondary)
            Spacer()
            if pagination.pageCount > 1 {
                Text("\(pagination.page + 1) / \(pagination.pageCount)")
                    .monospacedDigit().foregroundStyle(.secondary)
                Button { page = pagination.page - 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(pagination.page == 0).accessibilityLabel("上一页")
                Button { page = pagination.page + 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(pagination.page + 1 >= pagination.pageCount).accessibilityLabel("下一页")
            }
        }
        .font(.caption)
        .controlSize(.small)
        .frame(height: 24)
    }
}
