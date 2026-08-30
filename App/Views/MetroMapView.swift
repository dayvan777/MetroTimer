import SwiftUI

// Інтерактивна схема метро: ще один спосіб обрати станції, а не окремий світ.
// Перший дотик — «звідси», другий — «сюди»; маршрут підсвічується, решта
// пригасає, внизу — те саме резюме і та сама кнопка «Поїхали», що на головному
// екрані. Все малюється Canvas'ом з власної розкладки (MetroMapLayout):
// жодних мап-бібліотек, жодної мережі.
struct MetroMapView: View {
    @Binding var fromId: String?
    @Binding var toId: String?
    var onGo: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var engine: TripEngine
    @ObservedObject private var alertService = AlertService.shared

    @State private var scale: CGFloat = 0
    @State private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    private var repo: MetroRepository { engine.repo }
    private static let minScale: CGFloat = 0.3
    private static let maxScale: CGFloat = 3
    // Підписи з'являються, коли їх уже можна прочитати; раніше вони — шум.
    private static let labelScale: CGFloat = 0.75

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                canvas(in: geo.size)
                    .background(
                        LinearGradient(colors: [Color(red: 0.055, green: 0.06, blue: 0.082),
                                                Color(red: 0.03, green: 0.033, blue: 0.045)],
                                       startPoint: .top, endPoint: .bottom))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            scale = 0
                            fitIfNeeded(in: geo.size)
                        }
                    }
                    .onTapGesture(coordinateSpace: .local) { location in
                        tap(at: location, viewSize: geo.size)
                    }
                    .gesture(dragGesture(viewSize: geo.size)
                        .simultaneously(with: zoomGesture(viewSize: geo.size)))
                    .onAppear { fitIfNeeded(in: geo.size) }
                    // Перший прохід GeometryReader буває з нульовим розміром —
                    // добираємо fit, щойно розмір стане справжнім.
                    .onChange(of: geo.size) { fitIfNeeded(in: $0) }
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .bottom) { summaryCard }
            .navigationTitle(L10n.mapTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L10n.mapClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if fromId != nil || toId != nil {
                        Button(L10n.mapReset) {
                            withAnimation { fromId = nil; toId = nil }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Рендер

    private func canvas(in viewSize: CGSize) -> some View {
        // Маршрут для підсвітки перераховується тільки при зміні станцій.
        let route = routeStationIds()
        // Стан читаємо ТУТ, у тілі view, а не всередині замикання Canvas:
        // залежності SwiftUI реєструє при побудові view, і Canvas, який читає
        // @State лише під час малювання, після зміни стану не перемалюється.
        let effectiveScale = currentScale
        let effectiveOffset = currentOffset(viewSize: viewSize)
        return Canvas(rendersAsynchronously: false) { ctx, _ in
            ctx.translateBy(x: effectiveOffset.width, y: effectiveOffset.height)
            ctx.scaleBy(x: effectiveScale, y: effectiveScale)

            drawPaperGrid(&ctx)
            drawRiver(&ctx)
            drawHeading(&ctx)
            let dimmed = route != nil
            for line in repo.lines {
                drawLine(line, in: &ctx, route: route, dimmed: dimmed)
            }
            drawTransfers(&ctx, route: route)
            if route == nil { drawLineBadges(&ctx) }
            for line in repo.lines {
                for stationId in line.stationIds {
                    drawStation(stationId, line: line, in: &ctx,
                                route: route, dimmed: dimmed,
                                labelsVisible: effectiveScale >= Self.labelScale,
                                fontSize: min(36, max(7, 15.5 / effectiveScale)))
                }
            }
        }
    }

    // Точкова сітка: «папір», на якому надруковано схему.
    private func drawPaperGrid(_ ctx: inout GraphicsContext) {
        let step: CGFloat = 52
        var x: CGFloat = 28
        while x < MetroMapLayout.canvasSize.width {
            var y: CGFloat = 28
            while y < MetroMapLayout.canvasSize.height {
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.2, height: 2.2)),
                         with: .color(.white.opacity(0.045)))
                y += step
            }
            x += step
        }
    }

    private func drawRiver(_ ctx: inout GraphicsContext) {
        var path = Path()
        path.move(to: MetroMapLayout.riverStart)
        path.addCurve(to: MetroMapLayout.riverEnd,
                      control1: MetroMapLayout.riverControl1,
                      control2: MetroMapLayout.riverControl2)
        // Дві напівпрозорі стрічки замість однієї: м'який «акварельний» берег.
        ctx.stroke(path, with: .color(Color(red: 0.15, green: 0.25, blue: 0.42).opacity(0.30)),
                   style: StrokeStyle(lineWidth: MetroMapLayout.riverWidth * 1.9, lineCap: .round))
        ctx.stroke(path, with: .color(Color(red: 0.18, green: 0.30, blue: 0.50).opacity(0.35)),
                   style: StrokeStyle(lineWidth: MetroMapLayout.riverWidth, lineCap: .round))
        // Підпис уздовж течії.
        ctx.drawLayer { layer in
            layer.translateBy(x: 742, y: 236)
            layer.rotate(by: .degrees(83))
            layer.draw(Text("Д Н І П Р О")
                        .font(.system(size: 15, weight: .medium).italic())
                        .foregroundColor(Color(red: 0.45, green: 0.58, blue: 0.78).opacity(0.5)),
                       at: .zero, anchor: .leading)
        }
    }

    // Шапка схеми — скромна, без претензій на офіційність.
    private func drawHeading(_ ctx: inout GraphicsContext) {
        ctx.draw(Text("МЕТРО · КИЇВ")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(.white.opacity(0.92)),
                 at: CGPoint(x: 64, y: 64), anchor: .topLeading)
        ctx.draw(Text("3 лінії · 52 станції")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.4)),
                 at: CGPoint(x: 64, y: 102), anchor: .topLeading)
    }

    private func drawLine(_ line: Line, in ctx: inout GraphicsContext,
                          route: Set<String>?, dimmed: Bool) {
        let color = Color(hex: line.colorHex)
        let alertActive = alertService.state == .alert
        for (a, b) in zip(line.stationIds, line.stationIds.dropFirst()) {
            guard let pa = MetroMapLayout.point(a), let pb = MetroMapLayout.point(b) else { continue }
            var segment = Path()
            segment.move(to: pa)
            segment.addLine(to: pb)
            let onRoute = route?.contains(a) == true && route?.contains(b) == true
            let surface = repo.station(id: a)?.isSurface == true
                       && repo.station(id: b)?.isSurface == true
            // Під час тривоги наземні перегони гаснуть пунктиром: там не курсують.
            let width: CGFloat = onRoute ? 13 : 10
            let style = StrokeStyle(lineWidth: width,
                                    lineCap: .round,
                                    dash: alertActive && surface ? [5, 10] : [])
            let opacity: Double = dimmed && !onRoute ? 0.2 : 1
            // Темна «канва» під стрічкою — ефект друкованої схеми.
            ctx.stroke(segment, with: .color(Color(red: 0.03, green: 0.033, blue: 0.045)
                        .opacity(dimmed && !onRoute ? 0.3 : 0.9)),
                       style: StrokeStyle(lineWidth: width + 5, lineCap: .round))
            ctx.stroke(segment, with: .color(color.opacity(opacity)), style: style)
        }
    }

    private func drawTransfers(_ ctx: inout GraphicsContext, route: Set<String>?) {
        for transfer in repo.transfers {
            guard let pa = MetroMapLayout.point(transfer.fromId),
                  let pb = MetroMapLayout.point(transfer.toId) else { continue }
            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            let onRoute = route?.contains(transfer.fromId) == true
                       && route?.contains(transfer.toId) == true
            let opacity: Double = route != nil && !onRoute ? 0.22 : 0.92
            ctx.stroke(path, with: .color(Color(red: 0.03, green: 0.033, blue: 0.045)
                        .opacity(0.9)),
                       style: StrokeStyle(lineWidth: 10, lineCap: .round))
            ctx.stroke(path, with: .color(.white.opacity(opacity)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
    }

    private func drawStation(_ stationId: String, line: Line,
                             in ctx: inout GraphicsContext,
                             route: Set<String>?, dimmed: Bool, labelsVisible: Bool,
                             fontSize: CGFloat) {
        guard let point = MetroMapLayout.point(stationId),
              let station = repo.station(id: stationId) else { return }
        let spot = MetroMapLayout.spots[stationId]
        let color = Color(hex: line.colorHex)
        let onRoute = route?.contains(stationId) == true
        let isEndpoint = stationId == fromId || stationId == toId
        let faded = dimmed && !onRoute

        // «Бусина»: біла серцевина з обводкою в колір лінії — канон друкованих
        // схем. Пересадкова — більша; A/B — залитий кольором пін із літерою.
        let isTransfer = isTransferStation(stationId)
        let radius: CGFloat = isEndpoint ? 13 : (isTransfer ? 8.5 : 6)
        let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                         width: radius * 2, height: radius * 2))
        if isEndpoint {
            ctx.fill(dot, with: .color(color))
            ctx.stroke(dot, with: .color(.white), lineWidth: 3.5)
            let marker = stationId == fromId ? "A" : "B"
            ctx.draw(Text(marker).font(.system(size: 15, weight: .black))
                        .foregroundColor(.white),
                     at: CGPoint(x: point.x, y: point.y))
        } else {
            ctx.fill(dot, with: .color(.white.opacity(faded ? 0.35 : 0.96)))
            ctx.stroke(dot, with: .color(color.opacity(faded ? 0.3 : 1)),
                       lineWidth: isTransfer ? 4 : 3.2)
        }
        if station.isSurface {
            let halo = Path(ellipseIn: CGRect(x: point.x - radius - 4.5, y: point.y - radius - 4.5,
                                              width: (radius + 4.5) * 2, height: (radius + 4.5) * 2))
            ctx.stroke(halo, with: .color(color.opacity(faded ? 0.15 : 0.5)),
                       style: StrokeStyle(lineWidth: 1.4, dash: [3, 3.5]))
        }

        // На оглядовому зумі тісний центральний вузол підписуємо ОДИН раз —
        // імена пар (Театральна, Хрещатик, Площа) з'являться із наближенням.
        let primaryTransfer = ["zoloti-vorota", "maidan-nezalezhnosti", "palats-sportu"]
        let showLabel = labelsVisible
            || isTerminus(stationId, line: line)
            || (isTransferStation(stationId) && primaryTransfer.contains(stationId))
            || isEndpoint
        guard showLabel else { return }
        let name = station.localizedName
        let opacity: Double = faded ? 0.3 : (labelsVisible ? 0.97 : 0.85)
        let text = Text(name)
            .font(.system(size: fontSize,
                          weight: isEndpoint || isTransfer ? .bold : .semibold))
            .foregroundColor(.white.opacity(opacity))
        switch spot?.label ?? .right {
        case .right:
            drawLabel(text, in: &ctx, at: CGPoint(x: point.x + 16, y: point.y), anchor: .leading)
        case .left:
            drawLabel(text, in: &ctx, at: CGPoint(x: point.x - 16, y: point.y), anchor: .trailing)
        case .below:
            drawLabel(text, in: &ctx, at: CGPoint(x: point.x, y: point.y + 18), anchor: .top)
        case .above:
            drawLabel(text, in: &ctx, at: CGPoint(x: point.x, y: point.y - 18), anchor: .bottom)
        case .diag:
            // Підпис під 45° угору-праворуч — інакше горизонтальні промені
            // з кроком 44 пікселі перетворилися б на кашу.
            ctx.drawLayer { layer in
                layer.translateBy(x: point.x + 8, y: point.y - 10)
                layer.rotate(by: .degrees(-45))
                drawLabel(text, in: &layer, at: .zero, anchor: .leading)
            }
        }
    }

    // Підпис із темною підложкою: лінії і стрічка ріки під текстом більше
    // не з'їдають літери.
    private func drawLabel(_ text: Text, in ctx: inout GraphicsContext,
                           at point: CGPoint, anchor: UnitPoint) {
        let resolved = ctx.resolve(text)
        let size = resolved.measure(in: CGSize(width: 320, height: 40))
        var origin = CGPoint(x: point.x - size.width * anchor.x,
                             y: point.y - size.height * anchor.y)
        origin.x -= 3; origin.y -= 1.5
        let pad = CGRect(origin: origin,
                         size: CGSize(width: size.width + 6, height: size.height + 3))
        ctx.fill(Path(roundedRect: pad, cornerRadius: 4),
                 with: .color(Color(red: 0.05, green: 0.055, blue: 0.07).opacity(0.78)))
        ctx.draw(resolved, at: point, anchor: anchor)
    }

    // Кружечки «М1/М2/М3» біля кінцевих: миттєво зрозуміло, який промінь чий.
    private func drawLineBadges(_ ctx: inout GraphicsContext) {
        for line in repo.lines {
            guard let firstId = line.stationIds.first, let lastId = line.stationIds.last,
                  let first = MetroMapLayout.point(firstId),
                  let afterFirst = line.stationIds.dropFirst().first
                    .flatMap(MetroMapLayout.point),
                  let last = MetroMapLayout.point(lastId),
                  let beforeLast = line.stationIds.dropLast().last
                    .flatMap(MetroMapLayout.point) else { continue }
            let color = Color(hex: line.colorHex)
            let name = line.id.uppercased()
            for (end, prev) in [(first, afterFirst), (last, beforeLast)] {
                let dx = end.x - prev.x, dy = end.y - prev.y
                let len = max(1, (dx * dx + dy * dy).squareRoot())
                let center = CGPoint(x: end.x + dx / len * 34, y: end.y + dy / len * 34)
                let badge = Path(ellipseIn: CGRect(x: center.x - 13, y: center.y - 13,
                                                   width: 26, height: 26))
                ctx.fill(badge, with: .color(color))
                ctx.draw(Text(name).font(.system(size: 12.5, weight: .heavy))
                            .foregroundColor(.white),
                         at: center)
            }
        }
    }

    private func isTransferStation(_ id: String) -> Bool {
        repo.transfers.contains { $0.fromId == id || $0.toId == id }
    }

    private func isTerminus(_ id: String, line: Line) -> Bool {
        line.stationIds.first == id || line.stationIds.last == id
    }

    // Станції маршруту (для підсвітки) — той самий планувальник, що і всюди.
    private func routeStationIds() -> Set<String>? {
        guard let from = fromId, let to = toId,
              let trip = TripPlanner.plan(fromId: from, toId: to, start: Date(), repo: repo)
        else { return nil }
        return Set(trip.events.map(\.stationId) + [from])
    }

    // MARK: - Жести

    private var currentScale: CGFloat { scale * gestureScale }

    private func currentOffset(viewSize: CGSize) -> CGSize {
        CGSize(width: offset.width + gestureOffset.width,
               height: offset.height + gestureOffset.height)
    }

    private func fitIfNeeded(in viewSize: CGSize) {
        guard scale == 0, viewSize.width > 0, viewSize.height > 0 else { return }
        // Поля з боків: підписи кінцевих і бейджі ліній виступають за холст.
        let padX: CGFloat = 150, padY: CGFloat = 60
        let fit = min(viewSize.width / (MetroMapLayout.canvasSize.width + padX * 2),
                      viewSize.height / (MetroMapLayout.canvasSize.height + padY * 2))
        scale = fit
        offset = CGSize(
            width: (viewSize.width - MetroMapLayout.canvasSize.width * fit) / 2,
            height: (viewSize.height - MetroMapLayout.canvasSize.height * fit) / 2)
    }

    private func dragGesture(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in gestureOffset = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
                gestureOffset = .zero
                clampOffset(viewSize: viewSize)
            }
    }

    private func zoomGesture(viewSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in gestureScale = value }
            .onEnded { value in
                let target = min(max(scale * value, Self.minScale), Self.maxScale)
                // Масштабуємо навколо центру екрана, щоб карта не «тікала».
                let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                let factor = target / scale
                offset.width = center.x - (center.x - offset.width) * factor
                offset.height = center.y - (center.y - offset.height) * factor
                scale = target
                gestureScale = 1
                clampOffset(viewSize: viewSize)
            }
    }

    private func clampOffset(viewSize: CGSize) {
        let mapW = MetroMapLayout.canvasSize.width * scale
        let mapH = MetroMapLayout.canvasSize.height * scale
        let margin: CGFloat = 80
        offset.width = min(max(offset.width, viewSize.width - mapW - margin), margin)
        offset.height = min(max(offset.height, viewSize.height - mapH - margin), margin)
        if mapW < viewSize.width { offset.width = (viewSize.width - mapW) / 2 }
        if mapH < viewSize.height { offset.height = (viewSize.height - mapH) / 2 }
    }

    // MARK: - Вибір станцій

    private func tap(at location: CGPoint, viewSize: CGSize) {
        let off = currentOffset(viewSize: viewSize)
        let point = CGPoint(x: (location.x - off.width) / currentScale,
                            y: (location.y - off.height) / currentScale)
        // Радіус влучання — у пікселях екрана, не карти: на далекому зумі
        // палець однаково широкий.
        let hitRadius = 26 / currentScale
        var best: (id: String, distance: CGFloat)?
        for (id, spot) in MetroMapLayout.spots {
            let dx = spot.x - point.x, dy = spot.y - point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < hitRadius, distance < (best?.distance ?? .infinity) {
                best = (id, distance)
            }
        }
        guard let hit = best?.id, repo.station(id: hit)?.isClosed != true else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if hit == fromId { fromId = nil }
            else if hit == toId { toId = nil }
            else if fromId == nil { fromId = hit }
            else if toId == nil, hit != fromId { toId = hit }
            else { fromId = hit; toId = nil }
        }
    }

    // MARK: - Резюме внизу

    @ViewBuilder
    private var summaryCard: some View {
        VStack(spacing: 10) {
            if let from = fromId, let to = toId,
               let trip = TripPlanner.plan(fromId: from, toId: to, start: Date(), repo: repo) {
                let minutes = max(1, Int((trip.initialArrival.timeIntervalSince(trip.startDate) / 60).rounded()))
                let stops = trip.stopsRemaining(at: trip.startDate)
                let transferName = trip.events.first(where: \.isTransfer)?.displayName
                VStack(spacing: 4) {
                    Text("\(repo.station(id: from)?.localizedName ?? "") → \(repo.station(id: to)?.localizedName ?? "")")
                        .font(.subheadline.weight(.semibold))
                    Text([L10n.routeMinutes(minutes),
                          L10n.routeStops(stops),
                          transferName.map(L10n.routeTransfer)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    onGo()
                    dismiss()
                } label: {
                    Text(L10n.go)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(fromId == nil ? L10n.mapHintFrom : L10n.mapHintTo)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
