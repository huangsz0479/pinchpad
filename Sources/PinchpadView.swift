import AppKit
import SwiftUI

struct PinchpadRoot: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var screenEpoch = 0
    @State private var folderCard: FolderItem?
    @State private var folderShown = false

    @State private var clearHover = false

    private var isWindowed: Bool {
        model.settings.browsing == .window
    }

    var body: some View {
        ZStack {
            VStack(spacing: isWindowed ? 14 : 22) {
                searchField
                // 注意：这里不要加 offset/opacity 入场动画。面板渐显由 AppDelegate
                // 在图层树外层做（纯合成器动画），任何 SwiftUI 属性动画都会让
                // 渐显期间主线程逐帧重放显示列表，直接掉帧。
                if model.isOpen && model.isScanning && model.apps.isEmpty {
                    ProgressView("正在读取应用")
                        .controlSize(.large)
                        .tint(.white.opacity(0.85))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.visibleSlots.isEmpty {
                    empty
                } else {
                    grid
                }
                bottom
            }
            .padding(.horizontal, isWindowed ? 32 : 56)
            .padding(.top, isWindowed ? 32 : 72)
            .padding(.bottom, bottomPadding)
            .transaction { transaction in
                if folderCard != nil {
                    transaction.disablesAnimations = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .overlay {
            if model.query.isEmpty && model.settings.browsing == .paged && model.pages.count > 1 && (model.openFolder ?? folderCard) == nil {
                HStack {
                    if model.clampedPage > 0 {
                        PageArrowButton(direction: -1) { model.turnPage(-1) }
                            .padding(.leading, isWindowed ? 14 : 24)
                    } else {
                        Spacer().frame(width: 40).padding(.leading, isWindowed ? 14 : 24)
                    }
                    Spacer()
                    if model.clampedPage < model.pages.count - 1 {
                        PageArrowButton(direction: 1) { model.turnPage(1) }
                            .padding(.trailing, isWindowed ? 14 : 24)
                    } else {
                        Spacer().frame(width: 40).padding(.trailing, isWindowed ? 14 : 24)
                    }
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if let folder = model.openFolder ?? folderCard {
                FolderCover(folder: folder, model: model, shown: folderShown)
            }
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.white.opacity(0.9))
                    Text(notice)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
                .padding(.top, isWindowed ? 76 : 128)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(2.6))
                    if model.notice == notice { model.notice = nil }
                }
            }
        }
        .animation(.smooth(duration: 0.22), value: model.notice)
        .coordinateSpace(name: "pad")
        .onPreferenceChange(SlotFramesKey.self) { model.noteSlotFrames($0) }
        .background {
            ZStack {
                Color.black.opacity(model.settings.backdrop == .plain ? 0.72 : (model.settings.backdrop == .dim ? 0.38 : 0.18))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in model.closeFromPointer() })
                RadialGradient(
                    colors: [.clear, .black.opacity(0.3)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 900
                )
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            searchFocused = true
        }
        .onChange(of: model.isOpen) { _, open in
            if open && model.openFolderID == nil {
                folderCard = nil
                folderShown = false
            }
        }
        .onChange(of: model.openFolderID) { _, _ in
            presentFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenEpoch += 1
        }
        .onExitCommand { model.closeTop() }
        .onKeyPress(.leftArrow) {
            guard model.query.isEmpty, model.openFolderID == nil else { return .ignored }
            model.turnPage(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard model.query.isEmpty, model.openFolderID == nil else { return .ignored }
            model.turnPage(1)
            return .handled
        }
    }

    private func presentFolder() {
        if let folder = model.openFolder {
            let opening = folderCard == nil
            folderCard = folder
            guard opening else { return }
            folderShown = false
            DispatchQueue.main.async { folderShown = true }
        } else if folderCard != nil {
            folderShown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                if model.openFolderID == nil {
                    folderCard = nil
                }
            }
        }
    }

    private var bottomPadding: CGFloat {
        _ = screenEpoch
        return isWindowed ? 18 : 28
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(searchFocused ? 0.95 : 0.6))
            ZStack(alignment: .leading) {
                if model.query.isEmpty {
                    Text("搜索")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                        .allowsHitTesting(false)
                }
                TextField("", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .foregroundStyle(.white)
            }
            if !model.query.isEmpty {
                HStack(spacing: 6) {
                    Text("\(model.visibleSlots.count) 项")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.12), in: Capsule())

                    Button {
                        withAnimation(.smooth(duration: 0.18)) {
                            model.query = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(clearHover ? 0.95 : 0.55))
                            .scaleEffect(clearHover ? 1.12 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { clearHover = $0 }
                    .accessibilityLabel("清空搜索")
                    .help("清空搜索")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if searchFocused {
                Text("Esc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().fill(
                        LinearGradient(
                            colors: [.white.opacity(searchFocused ? 0.16 : 0.08), .white.opacity(searchFocused ? 0.06 : 0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .shadow(color: .black.opacity(searchFocused ? 0.35 : 0.2), radius: searchFocused ? 18 : 12, y: 5)
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    searchFocused
                        ? Color.white.opacity(0.55)
                        : Color.white.opacity(0.2),
                    lineWidth: searchFocused ? 1.5 : 1
                )
        }
        .frame(width: isWindowed ? 320 : 420)
        .animation(.smooth(duration: 0.18), value: searchFocused)
        .animation(.smooth(duration: 0.18), value: model.query.isEmpty)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.06))
                    .overlay { Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1) }
                    .frame(width: 84, height: 84)
                Image(systemName: model.query.isEmpty ? "square.grid.3x3.square" : "magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
            }
            VStack(spacing: 6) {
                Text(model.query.isEmpty ? "这里还没有应用" : "未找到匹配「\(model.query)」的应用")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(model.query.isEmpty ? "点击下方按钮重新扫描系统应用" : "请尝试其他关键词或应用名称")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Button {
                if model.query.isEmpty {
                    model.rescan()
                } else {
                    withAnimation(.smooth(duration: 0.2)) { model.query = "" }
                }
            } label: {
                if model.query.isEmpty {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                } else {
                    Label("清空搜索", systemImage: "xmark.circle")
                }
            }
            .buttonStyle(HoverPill(emphasized: true))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var grid: some View {
        if model.settings.browsing == .scroll || !model.query.isEmpty {
            ScrollingBoard(model: model)
        } else {
            JellyPages(model: model)
        }
    }

    private var bottom: some View {
        VStack(spacing: 14) {
            if !model.selection.isEmpty {
                HStack(spacing: 6) {
                    Text("已选 \(model.selection.count)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 1, height: 16)
                    Button {
                        model.makeFolder(from: selectedSlots)
                    } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(HoverPill(emphasized: true))
                    Button {
                        for slot in selectedSlots { model.hide(slot) }
                    } label: {
                        Label("隐藏应用", systemImage: "eye.slash")
                    }
                    .buttonStyle(HoverPill())
                    Button {
                        model.selection = []
                    } label: {
                        Label("取消", systemImage: "xmark")
                    }
                    .buttonStyle(HoverPill(subdued: true))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.query.isEmpty && model.settings.browsing == .paged && model.pages.count > 1 {
                PageIndicator(count: model.pages.count, current: model.clampedPage) { index in
                    model.showPage(index)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: model.selection.isEmpty)
    }

    private var selectedSlots: [Slot] {
        model.pages.flatMap(\.slots).filter { model.selection.contains($0.id) }
    }
}

private struct PageArrowButton: View {
    let direction: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.45))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(hovering ? 0.25 : 0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(hovering ? 0.35 : 0.15), radius: 10, y: 3)
                .scaleEffect(hovering ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(direction < 0 ? "上一页" : "下一页")
        .animation(.smooth(duration: 0.2), value: hovering)
    }
}

private struct HoverPill: ButtonStyle {
    var emphasized = false
    var subdued = false
    var danger = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(emphasized ? .semibold : .medium))
            .foregroundStyle(danger && hovering
                ? AnyShapeStyle(Color(nsColor: .systemRed))
                : AnyShapeStyle(Color.white.opacity(subdued ? (hovering ? 0.85 : 0.6) : (hovering ? 1 : 0.88))))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((danger && hovering ? Color(nsColor: .systemRed).opacity(0.16) : .white.opacity(hovering ? 0.16 : 0)), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .onHover { hovering = $0 }
            .animation(.smooth(duration: 0.15), value: hovering)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PageIndicator: View {
    let count: Int
    let current: Int
    let onSelect: (Int) -> Void
    @State private var hovering: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Button { onSelect(index) } label: {
                    Capsule()
                        .fill(index == current ? Color.white : Color.white.opacity(hovering == index ? 0.75 : 0.35))
                        .frame(width: index == current ? 20 : 6, height: 6)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 ? index : nil }
                .accessibilityLabel("第 \(index + 1) 页，共 \(count) 页")
                .accessibilityValue(index == current ? "当前页" : "")
                .help("第 \(index + 1) 页")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .animation(.smooth(duration: 0.25), value: current)
        .animation(.smooth(duration: 0.18), value: hovering)
    }
}

private struct GridMetrics: Equatable {
    var icon: CGFloat
    var plate: CGFloat
    var columnGap: CGFloat
    var rowGap: CGFloat
    var label: CGFloat

    var cellHeight: CGFloat { plate + label + 8 }

    static func fit(width: CGFloat, height: CGFloat, columns: Int, rows: Int, showsNames: Bool) -> GridMetrics {
        let columns = max(columns, 1)
        let rows = max(rows, 1)
        let label: CGFloat = showsNames ? 22 : 0
        let rowGap: CGFloat = 14
        let strideX = width / CGFloat(columns)
        let columnGap = min(68, strideX * 0.35)
        let cellH = (height - rowGap * CGFloat(rows - 1)) / CGFloat(rows)
        let plate = max(min(strideX - columnGap, cellH - label - 8), 32)
        let icon = plate
        return GridMetrics(icon: icon, plate: plate, columnGap: columnGap, rowGap: rowGap, label: label)
    }
}

private struct JellyPages: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let metrics = GridMetrics.fit(
                width: width * 0.92,
                height: geo.size.height - IconGrid.overflowPadding * 2,
                columns: model.settings.columns,
                rows: model.settings.rows,
                showsNames: !model.settings.hideNames
            )
            let page = model.clampedPage
            HStack(spacing: 0) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, _ in
                    // 只真正实例化当前页前后各一页：翻页动画只需要相邻页，
                    // 而离屏页如果也挂载，每次打开都会跟着播放入场波纹，
                    // 页数多时白烧主线程（也占内存）。
                    if abs(index - page) <= 1 {
                        let pageSlots = model.slots(on: index)
                        let capacity = max(model.settings.columns, 1) * max(model.settings.rows, 1)
                        let lastPageIsShort = index == model.pages.count - 1 && pageSlots.count < capacity
                        IconGrid(
                            model: model,
                            slots: pageSlots,
                            metrics: metrics,
                            columns: model.settings.columns,
                            pinsToStart: lastPageIsShort,
                            state: IconGrid.State(model, slots: pageSlots, isActivePage: index == page)
                        )
                        .equatable()
                        .frame(width: width, height: geo.size.height)
                    } else {
                        Color.clear
                            .frame(width: width, height: geo.size.height)
                    }
                }
            }
            .offset(x: -CGFloat(page) * width + model.swipeOffset)
            .animation(
                model.draggingID != nil ? .easeOut(duration: 0.16)
                    : (model.swiping ? nil : .spring(response: 0.42, dampingFraction: 0.84)),
                value: page
            )
            .animation(
                model.swiping ? nil : .spring(response: 0.42, dampingFraction: 0.84),
                value: model.swipeOffset
            )
            .frame(width: width, height: geo.size.height, alignment: .leading)
            .clipped()
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in model.closeFromPointer() })
            }
        }
    }
}

private struct ScrollingBoard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let columns = max(model.settings.columns, 1)
            let metrics = GridMetrics.fit(
                width: geo.size.width * 0.92,
                height: geo.size.height - IconGrid.overflowPadding * 2,
                columns: columns,
                rows: max(model.settings.rows, 1),
                showsNames: !model.settings.hideNames
            )
            ScrollView {
                IconGrid(model: model, slots: model.visibleSlots, metrics: metrics, columns: columns, state: IconGrid.State(model, slots: model.visibleSlots))
                    .equatable()
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.05),
                        .init(color: .black, location: 0.95),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in model.closeFromPointer() })
            }
        }
    }
}

private struct IconGrid: View, Equatable {
    struct State: Equatable {
        var draggingID: String?
        var folderHoverID: String?
        var selection: Set<String>
        var iconRevision: Int
        var libraryRevision: Int
        var hideNames: Bool
        var isOptionActive: Bool
        var jiggleTick: Int
        var bloomID: Int
        var entranceReset: Int

        @MainActor init(_ model: AppModel, slots: [Slot], isActivePage: Bool = true) {
            func local(_ id: String?) -> String? {
                guard let id, slots.contains(where: { $0.id == id }) else { return nil }
                return id
            }
            draggingID = local(model.draggingID)
            folderHoverID = local(model.folderHoverID)
            selection = model.selection.intersection(Set(slots.map(\.id)))
            iconRevision = model.iconRevision
            libraryRevision = model.libraryRevision
            hideNames = model.settings.hideNames
            // Option 抖动只给当前页：离屏页不需要逐帧重绘。
            // bloomID 则保持各页一致，否则翻页时「0 → 真实 bloomID」会被
            // BloomIn 当成一次新的入场波纹，出现莫名其妙的缩放/淡入。
            isOptionActive = isActivePage && model.isOptionPressed && model.settings.optionClickUninstall
            jiggleTick = isOptionActive ? model.jiggleTick : 0
            bloomID = model.bloomID
            entranceReset = model.entranceReset
        }
    }

    let model: AppModel
    var slots: [Slot]
    var metrics: GridMetrics
    var columns: Int
    var pinsToStart = false
    var state: State

    static func == (lhs: IconGrid, rhs: IconGrid) -> Bool {
        lhs.slots == rhs.slots && lhs.metrics == rhs.metrics && lhs.columns == rhs.columns
            && lhs.pinsToStart == rhs.pinsToStart && lhs.state == rhs.state
    }

    static let overflowPadding: CGFloat = 24
    private static let reorderSpring = Animation.spring(response: 0.3, dampingFraction: 0.78)

    var body: some View {
        let columnCount = max(columns, 1)
        let rowCount = max(Int((Double(max(slots.count, 1)) / Double(columnCount)).rounded(.up)), 1)
        let strideX = metrics.plate + metrics.columnGap
        let strideY = metrics.cellHeight + metrics.rowGap
        let gridWidth = CGFloat(columnCount) * metrics.plate + CGFloat(max(columnCount - 1, 0)) * metrics.columnGap
        let gridHeight = CGFloat(rowCount) * metrics.cellHeight + CGFloat(max(rowCount - 1, 0)) * metrics.rowGap
        // 入场波纹以网格中心为圆心向外扩散，呼应捏合展开的手势。
        // 按距离分 4 环：每个 SwiftUI 动画视图每帧都会标脏视图树，60 个格子各自动会打满主线程；
        // 同一环的格子一起进，动画单元降到 4 个。
        let centerX = Double(columnCount - 1) / 2
        let centerY = Double(rowCount - 1) / 2
        let maxDistance = max(sqrt(centerX * centerX + centerY * centerY), 1)
        let ringCount = 4
        let ringed: [[(index: Int, slot: Slot)]] = {
            var buckets: [[(index: Int, slot: Slot)]] = Array(repeating: [], count: ringCount)
            for (index, slot) in slots.enumerated() {
                let row = index / columnCount
                let column = index % columnCount
                let dx = Double(column) - centerX
                let dy = Double(row) - centerY
                let norm = sqrt(dx * dx + dy * dy) / maxDistance
                buckets[min(Int(norm * Double(ringCount)), ringCount - 1)].append((index, slot))
            }
            return buckets
        }()
        ZStack(alignment: .topLeading) {
            ForEach(0..<ringCount, id: \.self) { ring in
                BloomIn(bloomID: state.bloomID, delay: Double(ring) * 0.03, entranceReset: state.entranceReset) {
                    ZStack(alignment: .topLeading) {
                        ForEach(ringed[ring], id: \.slot.id) { item in
                            let row = item.index / columnCount
                            let column = item.index % columnCount
                            SlotCell(slot: item.slot, model: model, iconSide: metrics.icon, plate: metrics.plate)
                                .equatable()
                                .frame(width: metrics.plate, height: metrics.cellHeight)
                                .offset(x: CGFloat(column) * strideX, y: CGFloat(row) * strideY)
                                .zIndex(model.folderHoverID == item.slot.id ? 2 : (model.draggingID == item.slot.id ? 0 : 1))
                                .animation(Self.reorderSpring, value: slots)
                        }
                    }
                }
                .zIndex(
                    ringed[ring].contains { $0.slot.id == model.folderHoverID } ? 2
                        : (ringed[ring].contains { $0.slot.id == model.draggingID } ? 0 : 1)
                )
            }
        }
        .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: SlotFramesKey.self,
                    value: targetFrames(origin: geo.frame(in: .named("pad")).origin, columnCount: columnCount, strideX: strideX, strideY: strideY)
                )
            }
        }
        .padding(Self.overflowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pinsToStart ? .top : .center)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in model.closeFromPointer() })
        }
    }

    private func targetFrames(origin: CGPoint, columnCount: Int, strideX: CGFloat, strideY: CGFloat) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for (index, slot) in slots.enumerated() {
            let row = index / columnCount
            let column = index % columnCount
            frames[slot.id] = CGRect(
                x: origin.x + CGFloat(column) * strideX,
                y: origin.y + CGFloat(row) * strideY,
                width: metrics.plate,
                height: metrics.cellHeight
            )
        }
        return frames
    }
}

private struct SlotFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct SlotCell: View, Equatable {
    let slot: Slot
    let model: AppModel
    let iconSide: CGFloat
    let plate: CGFloat
    let app: AppItem?
    let folder: FolderItem?
    let image: NSImage?
    let previewImages: [NSImage]
    let selected: Bool
    let dragging: Bool
    let folderHover: Bool
    let showsName: Bool
    let isOptionActive: Bool
    let jiggleTick: Int
    @State private var hovering = false
    @State private var pressing = false

    init(slot: Slot, model: AppModel, iconSide: CGFloat, plate: CGFloat) {
        self.slot = slot
        self.model = model
        self.iconSide = iconSide
        self.plate = plate
        switch slot {
        case .app(let id):
            app = model.app(id)
            folder = nil
            image = app.map { model.icon(for: $0) }
            previewImages = []
        case .folder(let id):
            app = nil
            folder = model.folder(id)
            image = nil
            previewImages = (folder?.appIDs ?? []).prefix(9).compactMap { model.app($0) }.map { model.icon(for: $0) }
        }
        selected = model.selection.contains(slot.id)
        dragging = model.draggingID == slot.id
        folderHover = model.folderHoverID == slot.id
        showsName = !model.settings.hideNames
        isOptionActive = model.isOptionPressed && model.settings.optionClickUninstall
        jiggleTick = isOptionActive ? model.jiggleTick : 0
    }

    static func == (lhs: SlotCell, rhs: SlotCell) -> Bool {
        lhs.slot == rhs.slot && lhs.iconSide == rhs.iconSide && lhs.plate == rhs.plate
            && lhs.app == rhs.app && lhs.folder == rhs.folder && lhs.image === rhs.image
            && lhs.previewImages.elementsEqual(rhs.previewImages, by: ===)
            && lhs.selected == rhs.selected && lhs.dragging == rhs.dragging
            && lhs.folderHover == rhs.folderHover && lhs.showsName == rhs.showsName
            && lhs.isOptionActive == rhs.isOptionActive && lhs.jiggleTick == rhs.jiggleTick
    }

    /// 每个图标用自己的相位，左右交替摆动；松开 Option 后 tick 归零，角度恒为 0。
    private var jiggleAngle: Double {
        guard isOptionActive else { return 0 }
        var hash: UInt32 = 2166136261
        for byte in slot.id.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        let phase = Int(hash % 2)
        let direction = ((jiggleTick + phase) % 2 == 0) ? 1.0 : -1.0
        let amplitude = 1.2 + Double(hash % 5) * 0.12
        return direction * amplitude
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: plate * 0.24, style: .continuous)
                        .fill(Color.accentColor.opacity(0.2))
                        .overlay {
                            RoundedRectangle(cornerRadius: plate * 0.24, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                        }
                } else if hovering {
                    RadialGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: plate * 0.52
                    )
                }

                icon
                    .frame(width: iconSide, height: iconSide)
                    .compositingGroup()
                    .shadow(color: .black.opacity(hovering ? 0.28 : 0.18), radius: hovering ? 12 : 7, x: 0, y: hovering ? 6 : 3)
                    .scaleEffect(pressing && !dragging ? 0.84 : (folderHover ? 1.14 : (hovering ? 1.06 : 1)))
                    .animation(.spring(response: 0.26, dampingFraction: 0.76), value: folderHover)
                    .animation(.spring(response: 0.26, dampingFraction: 0.76), value: hovering)
                    .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressing)
            }
            .frame(width: plate, height: plate)
            .rotationEffect(.degrees(jiggleAngle))
            .animation(.easeInOut(duration: 0.09), value: jiggleTick)
            .animation(.easeOut(duration: 0.12), value: isOptionActive)
            .overlay(alignment: .topLeading) {
                if isOptionActive, let app, model.canUninstall(app) {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: .systemRed))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: -3, y: -3)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("按住 Option 点击可移到废纸篓：\(title)")
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor, in: Circle())
                        .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .offset(x: 5, y: -5)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: selected)
            if showsName {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(hovering ? 1.0 : 0.92))
                    .lineLimit(1)
                    .frame(width: plate + 12)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1.5)
                    .help(title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .opacity(dragging ? 0.28 : 1)
        .onHover { inside in
            let next = inside && model.interactionReady && model.draggingID == nil
            if hovering != next { hovering = next }
        }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                model.toggleSelect(slot)
            } else {
                model.activate(slot)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("pad"))
                .onChanged { _ in
                    if model.draggingID == nil {
                        model.beginDrag(slot.id)
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressing { pressing = true }
                }
                .onEnded { _ in pressing = false }
        )
        .contextMenu { menu }
        .accessibilityLabel(title)
    }

    @ViewBuilder private var icon: some View {
        switch slot {
        case .app:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            }
        case .folder:
            FolderIcon(images: previewImages, side: iconSide)
        }
    }

    private var title: String {
        switch slot {
        case .app: return app?.effectiveName ?? "应用"
        case .folder: return folder?.name ?? "文件夹"
        }
    }

    @ViewBuilder private var menu: some View {
        switch slot {
        case .app:
            if let app {
                Button {
                    model.launch(app)
                } label: {
                    Label("打开", systemImage: "arrow.up.forward.app")
                }
                Button {
                    model.reveal(app)
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
                Button {
                    model.rename(slot)
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                Button {
                    if app.hidden { model.unhide(app.id) } else { model.hide(slot) }
                } label: {
                    Label(app.hidden ? "取消隐藏" : "隐藏", systemImage: app.hidden ? "eye" : "eye.slash")
                }
                Button {
                    model.pinToDock(app)
                } label: {
                    Label("固定到 Dock", systemImage: "dock.rectangle")
                }
                Divider()
                Button(role: .destructive) {
                    model.promptUninstall(app)
                } label: {
                    Label("移到废纸篓", systemImage: "trash")
                }
            }
        case .folder(let id):
            Button {
                model.activate(slot)
            } label: {
                Label("打开", systemImage: "folder")
            }
            Button {
                model.rename(slot)
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                model.ungroup(id)
            } label: {
                Label("解散文件夹", systemImage: "rectangle.stack.badge.minus")
            }
        }
    }
}

private struct FolderIcon: View {
    let images: [NSImage]
    var side: CGFloat = 108

    var body: some View {
        let apps = images
        let (columns, rows): (CGFloat, CGFloat) = apps.count <= 4 ? (2, 2) : (3, 3)
        let plate = side * 0.8
        let padding = plate * 0.1
        let gap = plate * 0.04
        let mini = (plate - padding * 2 - gap * (columns - 1)) / columns
        let shape = RoundedRectangle(cornerRadius: plate * 0.225, style: .continuous)
        ZStack {
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.42), .white.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                }
                .frame(width: plate, height: plate)

            if apps.isEmpty {
                Image(systemName: "folder.fill")
                    .font(.system(size: plate * 0.4))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                VStack(spacing: gap) {
                    ForEach(0..<Int(rows), id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<Int(columns), id: \.self) { column in
                                let index = row * Int(columns) + column
                                if apps.indices.contains(index) {
                                    Image(nsImage: apps[index])
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: mini, height: mini)
                                } else {
                                    Color.clear.frame(width: mini, height: mini)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 图标出场的动画单元：每个环一组，从「还没出场」的隐藏态按 delay 依次弹出。
/// 动画只改 scale/opacity，都是合成器可以处理的属性；隐藏态用 1% 不透明度
/// 而不是 0，让图标纹理留在渲染进程里，弹出时不用重新光栅化。
private struct BloomIn<Content: View>: View {
    /// entranceReset 与 bloomID 必须放在同一个信号里观察：打开面板时两者在同一帧
    /// 变化，分开监听会互相吞掉（复位时顺手记下新的 bloomID，动画就永远不触发）。
    private struct Signal: Equatable {
        var reset: Int
        var bloom: Int
    }

    var bloomID: Int
    var delay: Double
    var entranceReset: Int = 0
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = true

    var body: some View {
        content
            .scaleEffect(appeared ? 1 : 0.82)
            .opacity(appeared ? 1 : 0.01)
            .onAppear {
                // 首次挂载（冷启动预热、翻页新挂载的相邻页）直接静态亮相；
                // 面板隐藏时 AppDelegate 会调用 prepareEntrance() 把它复位成隐藏态。
                appeared = true
            }
            .onChange(of: Signal(reset: entranceReset, bloom: bloomID)) { old, new in
                guard old != new else { return }
                if new.reset != old.reset {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { appeared = false }
                }
                if new.bloom != old.bloom {
                    bloomIn()
                }
            }
    }

    /// 先确保处于隐藏态（无动画），下一帧再按环的 delay 弹出。
    /// 刻意不放 .blur：SwiftUI 的 blur 是进程内逐帧重渲染的滤镜，几十个格子
    /// 一起跑会把 CPU 打满；纯 scale/opacity 变换才能跑在合成器里。
    private func bloomIn() {
        guard !reduceMotion else {
            appeared = true
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { appeared = false }
        DispatchQueue.main.async {
            // 用固定时长的 easeOut 而不是长 spring：位移均匀铺在整段 0.22s 里，
            // 60fps 下每一帧都有肉眼可见的变化；也不会像长 spring 那样拖出半秒尾巴。
            withAnimation(.easeOut(duration: 0.22).delay(delay)) {
                appeared = true
            }
        }
    }
}

private struct FolderCover: View {
    let folder: FolderItem
    @ObservedObject var model: AppModel
    var shown: Bool
    @State private var draft = ""
    @State private var titleHover = false
    @State private var confirmUngroup = false
    @FocusState private var nameFocused: Bool

    private var appIDs: [String] {
        folder.appIDs.filter { model.app($0) != nil }
    }

    private var displayName: String {
        model.folder(folder.id)?.name ?? folder.name
    }

    var body: some View {
        GeometryReader { geometry in
            card(in: geometry.size)
        }
    }

    private func card(in available: CGSize) -> some View {
        let count = max(appIDs.count, 1)
        let cellWidth: CGFloat = 160
        let cellHeight: CGFloat = 188
        let columnSpacing: CGFloat = 28
        let rowSpacing: CGFloat = 20
        let chrome: CGFloat = 133
        let wantedColumns = count <= 3 ? count : (count <= 8 ? 4 : (count <= 15 ? 5 : 6))
        let fitColumns = max(1, Int((available.width - 136) / (cellWidth + columnSpacing)))
        let columns = min(wantedColumns, fitColumns)
        let rowCount = (count + columns - 1) / columns
        let contentWidth = CGFloat(columns) * cellWidth + CGFloat(columns - 1) * columnSpacing
        let contentHeight = CGFloat(rowCount) * cellHeight + CGFloat(rowCount - 1) * rowSpacing
        let cardWidth = min(contentWidth + 68, max(available.width - 64, 300))
        let cardHeight = min(chrome + contentHeight + 24, max(available.height - 96, 260))
        let scrollArea = cardHeight - chrome - 24

        return ZStack {
            Color.black.opacity(shown ? 0.35 : 0)
                .contentShape(Rectangle())
                .allowsHitTesting(shown)
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in model.openFolderID = nil })
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    HStack {
                        Button {
                            model.openFolderID = nil
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.12), in: Circle())
                                .overlay { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("返回应用列表")
                        Spacer()
                        Button {
                            confirmUngroup = true
                        } label: {
                            Label("解散", systemImage: "rectangle.stack.badge.minus")
                        }
                        .buttonStyle(HoverPill(subdued: true, danger: true))
                    }
                    VStack(spacing: 3) {
                        folderTitle
                        Text("\(appIDs.count) 个应用")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)
                ScrollView(.vertical) {
                    VStack(spacing: rowSpacing) {
                        ForEach(0..<rowCount, id: \.self) { row in
                            HStack(alignment: .top, spacing: columnSpacing) {
                                ForEach(0..<columns, id: \.self) { column in
                                    let index = row * columns + column
                                    if appIDs.indices.contains(index) {
                                        BloomIn(bloomID: model.bloomID, delay: Double(index) * 0.025) {
                                            SlotCell(slot: .app(appIDs[index]), model: model, iconSide: 104, plate: 132)
                                                .equatable()
                                                .frame(width: cellWidth, height: cellHeight)
                                        }
                                    } else {
                                        Color.clear.frame(width: cellWidth, height: cellHeight)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: max(scrollArea, 0), alignment: contentHeight <= scrollArea ? .center : .top)
                }
                .scrollIndicators(contentHeight > scrollArea ? .visible : .hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.45), radius: 36, x: 0, y: 14)
            .scaleEffect(shown ? 1 : 0.94, anchor: .center)
            .offset(y: shown ? 0 : 12)
            .opacity(shown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(shown ? Self.folderOpenAnim : Self.folderCloseAnim, value: shown)
        .alert("解散「\(displayName)」？", isPresented: $confirmUngroup) {
            Button("取消", role: .cancel) {}
            Button("解散文件夹", role: .destructive) { model.ungroup(folder.id) }
        } message: {
            Text("其中的应用不会删除，会回到应用列表。")
        }
    }

    private static let folderOpenAnim = Animation.spring(response: 0.38, dampingFraction: 0.82)
    private static let folderCloseAnim = Animation.spring(response: 0.26, dampingFraction: 0.92)

    @ViewBuilder private var folderTitle: some View {
        if model.folderNameEditing {
            TextField("文件夹名称", text: $draft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1) }
                .frame(maxWidth: 260)
                .focused($nameFocused)
                .onSubmit { model.renameFolder(folder.id, to: draft) }
                .onAppear {
                    draft = displayName
                    nameFocused = true
                }
        } else {
            Button {
                draft = displayName
                model.folderNameEditing = true
            } label: {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(titleHover ? 0.75 : 0))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(titleHover ? 0.1 : 0), in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { titleHover = $0 }
            .accessibilityLabel("重命名文件夹：\(displayName)")
            .animation(.smooth(duration: 0.18), value: titleHover)
        }
    }
}
