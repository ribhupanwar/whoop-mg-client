import SwiftUI
import CoreText
import UIKit


// MARK: - Typography
// Bundled Proxima Nova and DIN Pro; keep font weight explicit to avoid thin fallbacks.
enum StrapTypography {
    private static let files = ["ProximaNova-Regular", "ProximaNova-Bold", "ProximaNova-Light",
        "ProximaNova-RegularIt", "ProximaNova-BoldIt", "ProximaNova-LightIt",
        "proxima-nova-medium", "proxima-nova-semibold", "DINPro-Regular", "DINPro-Light", "DINPro-Bold"]
    private static let descriptors: [String: CTFontDescriptor] = {
        var result: [String: CTFontDescriptor] = [:]
        for file in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: file, withExtension: "ttf"),
                let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                let descriptor = list.first else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            result[file] = descriptor
        }
        return result
    }()
    private final class ResolvedFont: NSObject {
        let coreText: CTFont
        let swiftUI: Font
        init(_ descriptor: CTFontDescriptor, size: CGFloat) {
            let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            coreText = font
            swiftUI = Font(font)
            super.init()
        }
    }
    private static let cache = NSCache<NSString, ResolvedFont>()
    private static let cacheLock = NSLock()

    private static func resolved(_ file: String, size: CGFloat) -> ResolvedFont? {
        let key = "\(file):\(size)" as NSString
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache.object(forKey: key) { return cached }
        guard let descriptor = descriptors[file] else { return nil }
        let result = ResolvedFont(descriptor, size: size)
        cache.setObject(result, forKey: key)
        return result
    }
    /// Inspect the actual CoreText face handed to SwiftUI, not a successful
    /// UIFont name lookup that can conceal a substituted family or weight.
    static func resolvedPostScriptName(_ file: String, size: CGFloat = 15) -> String? {
        resolved(file, size: size).map { CTFontCopyPostScriptName($0.coreText) as String }
    }
    static var missingBundledFaces: [String] {
        files.filter { file in
            let expected = file == "proxima-nova-medium" ? "ProximaNova-Medium"
                : file == "proxima-nova-semibold" ? "ProximaNova-Semibold" : file
            return resolvedPostScriptName(file) != expected
        }
    }
    static func configureUIKitAppearance() {
        guard let regularName = resolvedPostScriptName("ProximaNova-Regular"),
              let boldName = resolvedPostScriptName("ProximaNova-Bold"),
              let regular = UIFont(name: regularName, size: 17),
              let bold = UIFont(name: boldName, size: 17) else { return }
        let navigation = UINavigationBarAppearance()
        navigation.configureWithDefaultBackground()
        navigation.titleTextAttributes = [.font: bold, .foregroundColor: UIColor.label, .kern: 1.3]
        navigation.largeTitleTextAttributes = [.font: UIFont(name: boldName, size: 34) ?? bold,
                                               .foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().tintColor = UIColor(Color.appAccent)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: regular], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: regular], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: bold], for: .selected)
        UIRefreshControl.appearance().tintColor = .clear
    }
    private static func bodyFile(_ weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black { return "ProximaNova-Bold" }
        if weight == .semibold { return "proxima-nova-semibold" }
        if weight == .medium { return "proxima-nova-medium" }
        if weight == .light || weight == .ultraLight { return "ProximaNova-Light" }
        return "ProximaNova-Regular"
    }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        resolved(bodyFile(weight), size: size)?.swiftUI ?? .system(size: size, weight: weight)
    }
    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let face = weight == .regular ? "Regular" : (weight == .light || weight == .ultraLight) ? "Light" : "Bold"
        return (resolved("DINPro-\(face)", size: size)?.swiftUI ?? .system(size: size, weight: weight)).monospacedDigit()
    }
}

// MARK: - Screen scaffolding

/// Scrollable dark screen. Shows the sample-data banner on every screen
/// whenever design preview is ON; live mode never shows it.
struct Screen<Content: View>: View {
    @EnvironmentObject private var store: AppStore
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.isPreview {
                    DemoBanner()
                }
                content
            }
            .padding(.horizontal, AppLayout.screenInset)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .font(StrapTypography.body(15))
        .background(
            LinearGradient.appCanvas
                .ignoresSafeArea()
        )
    }
}

struct DemoBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Design preview — sample data")
                .font(StrapTypography.body(12, weight: .bold))
                .foregroundStyle(Color.appFG)
            Text("Values marked sample are invented to show the finished layout. They are not your measurements.")
                .font(StrapTypography.body(11.5))
                .foregroundStyle(Color.appMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.appDemoFlagBG))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appWarn, lineWidth: 1))
        .padding(.bottom, 12)
    }
}

/// Surface card with hairline border, matching the mockup's rm-card/rm-panel.
struct Panel<Content: View>: View {
    private let content: Content
    private let gradient: LinearGradient

    init(gradient: LinearGradient = .appCard, @ViewBuilder content: () -> Content) {
        self.gradient = gradient
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppLayout.cardInset)
        .background(RoundedRectangle(cornerRadius: AppLayout.cardRadius).fill(gradient))
        .padding(.bottom, AppLayout.cardSpacing)
    }
}

/// Accent-edged callout box (mockup rm-cta).
struct CTABox<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.appAccent).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 11)
    }
}

struct CardHead: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(StrapTypography.body(11.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.appFG)
            Spacer()
            if let trailing {
                if trailing == "\u{203A}" || trailing == "›" {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.appMuted)
                } else if trailing == "\u{2922}" || trailing == "⤢" {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.appMuted)
                } else {
                    Text(trailing)
                        .font(StrapTypography.body(14))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
        .padding(.bottom, 11)
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(StrapTypography.body(12, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.appMuted)
            .padding(.bottom, 8)
    }
}

struct Hint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(StrapTypography.body(11))
            .foregroundStyle(Color.appMuted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 9)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(StrapTypography.body(14, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text(detail)
                .font(StrapTypography.body(12))
                .foregroundStyle(Color.appMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
    }
}

// MARK: - Rings and bars

/// Activity ring. `progress == nil` renders an empty track (live, unmeasured).
struct RingView: View {
    let progress: Double?
    let color: Color
    var lineWidth: CGFloat = AppLayout.ringStrokeWidth
    var size: CGFloat = AppLayout.heroRingDiameter
    let centerText: String
    var centerFont: CGFloat = AppLayout.heroMetricFontSize

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.appRingTrack, lineWidth: lineWidth)
            if let progress, progress > 0 {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .padding(lineWidth / 2)
                    .rotationEffect(.degrees(-90))
            }
            ScoreValueText(value: centerText, size: centerFont)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .foregroundStyle(Color.appFG)
        }
        .frame(width: size, height: size)
    }
}

/// Numeric score typography shared by score rings and the full-size score hero.
/// WHOOP-style score values use the bundled DIN Pro face; percent signs are
/// intentionally smaller than the score digits. Labels remain Proxima Nova.
struct ScoreValueText: View {
    let value: String
    let size: CGFloat
    var weight: Font.Weight = .bold

    var body: some View {
        if value.hasSuffix("%"), value.count > 1 {
            HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                Text(String(value.dropLast()))
                    .font(StrapTypography.metric(size, weight: .bold))
                Text("%")
                    .font(StrapTypography.metric(size * AppLayout.percentSignScale, weight: .bold))
            }
            .monospacedDigit()
        } else {
            Text(value)
                .font(StrapTypography.metric(size, weight: weight))
                .monospacedDigit()
        }
    }
}

struct MiniProgress: View {
    let fraction: Double?
    var color: Color = .appSleep

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appRaised)
                if let fraction {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                }
            }
        }
        .frame(height: 6)
    }
}

struct SplitBar: View {
    struct Segment {
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segment.color
                        .frame(width: geo.size.width * CGFloat(min(max(segment.fraction, 0), 1)))
                }
            }
        }
        .frame(height: 11)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Charts (hand-rolled, no dependencies)

struct LineChart: View {
    let values: [Double]
    var color: Color = .appAccent
    var minY: Double? = nil
    var maxY: Double? = nil
    var height: CGFloat = 120
    var yLabels: [String] = []
    var xLabels: [String] = []

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lo = minY ?? (values.min() ?? 0)
            let hi = maxY ?? (values.max() ?? 1)
            let range = max(hi - lo, 0.0001)
            let leftPad: CGFloat = yLabels.isEmpty ? 0 : 26
            let bottomPad: CGFloat = xLabels.isEmpty ? 0 : 14
            let plotW = max(w - leftPad, 1)
            let plotH = max(h - bottomPad, 1)
            let gridFractions: [CGFloat] = yLabels.isEmpty
                ? [0, 0.5, 1]
                : yLabels.indices.map { CGFloat($0) / CGFloat(max(yLabels.count - 1, 1)) }

            ZStack(alignment: .topLeading) {
                ForEach(Array(gridFractions.enumerated()), id: \.offset) { _, fraction in
                    Path { p in
                        let y = plotH * fraction
                        p.move(to: CGPoint(x: leftPad, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.appLine, lineWidth: 1)
                }
                if values.count > 1 {
                    Path { p in
                        for (i, value) in values.enumerated() {
                            let x = leftPad + plotW * CGFloat(i) / CGFloat(values.count - 1)
                            let clamped = min(max(value, lo), hi)
                            let y = plotH * (1 - CGFloat((clamped - lo) / range))
                            if i == 0 {
                                p.move(to: CGPoint(x: x, y: y))
                            } else {
                                p.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(yLabels.enumerated()), id: \.offset) { idx, label in
                    Text(label)
                        .font(StrapTypography.body(9))
                        .foregroundStyle(Color.appMuted)
                        .position(
                            x: leftPad / 2,
                            y: plotH * CGFloat(idx) / CGFloat(max(yLabels.count - 1, 1))
                        )
                }
                ForEach(Array(xLabels.enumerated()), id: \.offset) { idx, label in
                    Text(label)
                        .font(StrapTypography.body(9))
                        .foregroundStyle(Color.appMuted)
                        .position(
                            x: leftPad + plotW * CGFloat(idx) / CGFloat(max(xLabels.count - 1, 1)),
                            y: h - 7
                        )
                }
            }
        }
        .frame(height: height)
    }
}

struct BarChart: View {
    let values: [Double]
    let labels: [String]
    var maxValue: Double = 100
    var color: Color = .appSleep
    var height: CGFloat = 130

    var body: some View {
        GeometryReader { geo in
            let barMax = max(geo.size.height - 34, 4)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        Text("\(Int(value))")
                            .font(StrapTypography.metric(9, weight: .regular))
                            .foregroundStyle(Color.appMuted)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(height: max(2, barMax * CGFloat(min(max(value / maxValue, 0), 1))))
                        Text(idx < labels.count ? labels[idx] : "")
                            .font(StrapTypography.body(9))
                            .foregroundStyle(Color.appMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: height)
    }
}

/// Stacked vertical bars: each bar is a list of segment heights (top first),
/// scaled against maxValue. Used for the weekly sleep-stress split.
struct StackedBarChart: View {
    let bars: [[Double]]
    let colors: [Color]
    let labels: [String]
    var maxValue: Double = 100
    var height: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            let barMax = max(geo.size.height - 20, 4)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { idx, segments in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 0) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { si, value in
                                (si < colors.count ? colors[si] : Color.appMuted)
                                    .frame(height: max(0, barMax * CGFloat(min(max(value / maxValue, 0), 1))))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(idx < labels.count ? labels[idx] : "")
                            .font(StrapTypography.body(9))
                            .foregroundStyle(Color.appMuted)
                            .padding(.top, 3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: height)
    }
}

/// Vertical bedâ†’wake range bars on a shared time axis (0â€¦axisMax). Each span
/// is (top, bottom) in axis units; top < bottom. Used for consistency and
/// time-in-bed charts.
struct BedWakeChart: View {
    let spans: [(Double, Double)]
    let labels: [String]
    var axisMax: Double = 780
    var height: CGFloat = 150
    var highlightLast: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let plotH = max(geo.size.height - 18, 4)
            let n = max(spans.count, 1)
            let slot = w / CGFloat(n)
            let barW = min(slot * 0.55, 26)
            ZStack(alignment: .topLeading) {
                ForEach([0.25, 0.5, 0.75], id: \.self) { f in
                    Path { p in
                        let y = plotH * CGFloat(f)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.appLine, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                ForEach(Array(spans.enumerated()), id: \.offset) { idx, span in
                    let top = plotH * CGFloat(min(max(span.0 / axisMax, 0), 1))
                    let bottom = plotH * CGFloat(min(max(span.1 / axisMax, 0), 1))
                    let isLast = highlightLast && idx == spans.count - 1
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isLast ? Color.appSleep : Color.appRaised)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                        .frame(width: barW, height: max(bottom - top, 2))
                        .position(x: slot * (CGFloat(idx) + 0.5), y: (top + bottom) / 2)
                }
                ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                    Text(label)
                        .font(StrapTypography.body(9))
                        .foregroundStyle(Color.appMuted)
                        .position(x: slot * (CGFloat(idx) + 0.5), y: geo.size.height - 8)
                }
            }
        }
        .frame(height: height)
    }
}

/// Small colour-key legend row.
struct ChartLegend: View {
    let items: [(String, Color)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(item.1).frame(width: 14, height: 3)
                    Text(item.0).font(StrapTypography.body(10)).foregroundStyle(Color.appMuted)
                }
            }
        }
        .padding(.top, 6)
    }
}

// Original, reference-inspired 24-unit outline pictograms. No third-party artwork.
// All paths use a shared optical grid; tint is inherited from the owning surface.
struct ReferencePictogram: View {
    let symbol: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let path = Self.outline(for: symbol) {
                path.applying(CGAffineTransform(scaleX: size / 24, y: size / 24))
                    .stroke(style: StrokeStyle(lineWidth: 1.45 * size / 24, lineCap: .round, lineJoin: .round))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.9, weight: .light))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func outline(for symbol: String) -> Path? {
        var p = Path()
        func move(_ x: CGFloat, _ y: CGFloat) { p.move(to: CGPoint(x: x, y: y)) }
        func line(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: CGPoint(x: x, y: y)) }
        func curve(_ x: CGFloat, _ y: CGFloat, _ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) {
            p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: d))
        }
        func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            p.addEllipse(in: CGRect(x: x, y: y, width: w, height: h))
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 1.5) {
            p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: r, height: r))
        }
        func heart() {
            move(12, 20); curve(3, 10, 9, 17, 3, 13); curve(12, 6, 3, 4, 9, 3)
            curve(21, 10, 15, 3, 21, 4); curve(12, 20, 21, 13, 15, 17); p.closeSubpath()
        }
        func pulse() {
            move(2.5, 11); line(8, 11); line(12.4, 4.5); curve(14.6, 5.5, 13.4, 3.3, 15.3, 3.9)
            line(12.7, 10); line(20.5, 10); curve(20.5, 13, 22.5, 10, 22.5, 13)
            line(13.8, 13); line(9.6, 19); curve(7.6, 18, 8.6, 20.1, 7, 19.4)
            line(9, 14); line(3, 14); curve(2.5, 11, 1, 14, 1, 11); p.closeSubpath()
        }
        func lungs() {
            move(12, 3); line(12, 9); line(8.5, 12); move(12, 9); line(15.5, 12)
            move(9.5, 6); curve(5.5, 7, 8, 4, 7, 5); curve(2.5, 17, 3, 10, 2, 15)
            curve(6, 19.5, 2.5, 19.5, 4, 20.5); curve(10, 17, 8, 19, 10, 19); line(10, 11)
            move(14.5, 6); curve(18.5, 7, 16, 4, 17, 5); curve(21.5, 17, 21, 10, 22, 15)
            curve(18, 19.5, 21.5, 19.5, 20, 20.5); curve(14, 17, 16, 19, 14, 19); line(14, 11)
        }
        func moon() {
            move(14, 3); curve(21, 16, 8, 12, 15, 19)
            curve(5, 19, 17, 23, 9, 23); curve(14, 3, 0, 12, 5, 4); p.closeSubpath()
        }
        switch symbol {
        case "waveform.path.ecg": pulse()
        case "heart.pulse":
            move(10, 18); curve(2, 9, 6, 15, 2, 12); curve(10, 5.5, 2, 4, 7, 3)
            curve(17, 9, 13, 3, 17, 4); curve(10, 18, 17, 12, 13, 15)
            move(20, 8); line(20, 17); move(16.5, 13.5); line(20, 17); line(23, 13.5)
        case "figure.walk":
            move(8, 3); line(12, 6); line(10.5, 10); curve(14, 14, 11, 12, 13, 13)
            line(19, 15.5); curve(21, 19.5, 21, 16, 22, 18); line(11, 19.5); line(3, 11.5)
            curve(3.5, 8, 2, 10, 2, 9); line(8, 3); p.closeSubpath()
            move(5, 8); line(13, 17); line(21, 17); move(10.5, 10); line(14, 8)
            move(7, 4); line(10, 7)
        case "zones.low", "zones.high":
            heart()
            if symbol == "zones.low" {
                move(7.5, 13); line(16.5, 13); move(9.5, 15.5); line(14.5, 15.5)
            } else {
                move(5, 10); line(8.5, 7.5); line(12, 10); line(15.5, 7.5); line(19, 10)
                move(5, 12); line(19, 12)
            }
        case "dumbbell":
            rect(4.5, 5, 3, 14); rect(16.5, 5, 3, 14); rect(1.5, 8, 3, 8); rect(19.5, 8, 3, 8)
            move(7.5, 10.5); line(16.5, 10.5); move(7.5, 13.5); line(16.5, 13.5)
        case "lungs", "wind": lungs()
        case "flame":
            move(11, 2.5); curve(16, 11, 17, 5, 18, 8)
            curve(20, 15, 19, 10, 21, 12); curve(12, 21, 20, 19, 16, 21)
            curve(4, 15, 7, 21, 3, 19); curve(10, 7, 4, 11, 10, 10)
            curve(11, 2.5, 12, 5, 11, 4); p.closeSubpath()
            move(13, 12); curve(12, 19, 8, 15, 9, 19); curve(15, 16, 15, 19, 16, 17)
        case "drop":
            move(11, 3); curve(18, 15, 13, 7, 18, 11); curve(11, 21, 18, 19, 15, 21)
            curve(4, 15, 7, 21, 4, 19); curve(11, 3, 4, 11, 9, 7); p.closeSubpath()
            move(7, 15); curve(10, 18, 7, 17, 8, 18); oval(17.5, 3, 3, 3)
        case "thermometer":
            move(9, 14); line(9, 5); curve(15, 5, 9, 1.5, 15, 1.5); line(15, 14)
            curve(12, 22, 21, 20, 15, 23); curve(9, 14, 5, 22, 4, 18); p.closeSubpath()
            oval(10, 16, 4, 4); move(12, 7); line(12, 16)
        case "nav.home":
            move(2, 11); line(12, 3); line(22, 11); move(5, 10); line(5, 21); line(19, 21); line(19, 10)
            move(8, 16); line(11, 13); line(14, 15); line(17, 11)
        case "nav.health":
            heart(); move(5, 11); line(9, 11); line(11, 8); line(14, 15); line(16, 11); line(19, 11)
        case "nav.humans":
            oval(9.5, 2.5, 5, 5.5); oval(2.5, 5, 4, 5); oval(17.5, 5, 4, 5)
            move(8, 21); line(8, 13); curve(16, 13, 8, 9, 16, 9); line(16, 21)
            move(2, 19); line(2, 14); curve(6, 12, 2, 11, 5, 11)
            move(18, 12); curve(22, 14, 21, 11, 22, 12); line(22, 19)
        case "nav.more":
            move(9, 5); line(22, 5); move(12, 11); line(22, 11); move(12, 18); line(22, 18)
            rect(2, 12, 7, 7, 0.8); move(1, 12); line(10, 12); move(5.5, 12); line(5.5, 19)
            move(5.5, 12); curve(2, 9, 0, 11, 0, 7); curve(5.5, 12, 4, 8, 5, 10)
            curve(9, 9, 6, 10, 8, 8); curve(5.5, 12, 11, 10, 10, 11)
        case "applewatch":
            oval(7, 2, 13, 20); move(11, 2); curve(5, 21, 3, 3, 1, 19)
            line(13, 22); move(4.5, 6); line(11, 6); move(3, 16); line(10, 16)
        case "arrow.triangle.2.circlepath":
            move(3, 10); curve(20, 8, 5, 2, 16, 2); move(16, 8); line(20, 8); line(20, 4)
            move(21, 14); curve(4, 16, 19, 22, 8, 22); move(8, 16); line(4, 16); line(4, 20)
        case "alarm":
            oval(4, 5, 16, 16); move(12, 8); line(12, 13); line(15, 15)
            move(3, 5); line(6, 2); move(18, 2); line(21, 5)
        case "moon.stars": moon(); move(19, 3); line(19, 7); move(17, 5); line(21, 5)
        case "book.closed":
            rect(5, 3, 14, 18); move(8, 3); line(8, 21); move(11, 8); line(16, 8); move(11, 12); line(16, 12)
        case "calendar":
            rect(3, 5, 18, 16); move(3, 10); line(21, 10); move(8, 3); line(8, 7); move(16, 3); line(16, 7)
            for x in [CGFloat(7), 12, 17] { oval(x - 0.6, 14, 1.2, 1.2) }
        case "link.circle":
            oval(9, 9, 6, 6); oval(9, 1.5, 6, 5); oval(2, 17, 6, 5); oval(16, 17, 6, 5)
            move(12, 6.5); line(12, 9); move(9.5, 14); line(7, 17); move(14.5, 14); line(17, 17)
        case "tray.and.arrow.down":
            move(3, 13); line(6, 6); line(18, 6); line(21, 13); line(21, 20); line(3, 20); p.closeSubpath()
            move(3, 13); line(9, 13); line(10, 16); line(14, 16); line(15, 13); line(21, 13)
            move(12, 2); line(12, 10); move(9, 7); line(12, 10); line(15, 7)
        case "clock.arrow.circlepath":
            move(3, 10); curve(12, 3, 4, 6, 8, 3); curve(21, 12, 17, 3, 21, 7)
            curve(12, 21, 21, 17, 17, 21); curve(3, 14, 7, 21, 4, 18)
            move(3, 4); line(3, 10); line(9, 10); move(12, 7); line(12, 12); line(16, 14)
        case "heart.text.square":
            rect(3, 3, 18, 18); move(12, 14); curve(7, 9, 9, 12, 7, 11)
            curve(12, 7, 7, 6, 10, 6); curve(17, 9, 14, 6, 17, 6)
            curve(12, 14, 17, 11, 14, 12); move(7, 17); line(17, 17)
        case "bell":
            move(5, 16); curve(7, 8, 7, 14, 7, 11); curve(17, 8, 7, 2, 17, 2)
            curve(19, 16, 17, 11, 17, 14); line(21, 18); line(3, 18); line(5, 16)
            move(9, 20); curve(15, 20, 10, 23, 14, 23)
        case "gearshape":
            oval(8, 8, 8, 8)
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4
                let next = angle + .pi / 8
                move(12 + 9 * cos(angle), 12 + 9 * sin(angle))
                line(12 + 11 * cos(angle), 12 + 11 * sin(angle))
                line(12 + 11 * cos(next), 12 + 11 * sin(next))
                line(12 + 9 * cos(next), 12 + 9 * sin(next))
                let end = angle + .pi / 4
                line(12 + 9 * cos(end), 12 + 9 * sin(end))
            }
        case "square.grid.2x2":
            rect(3, 3, 7, 7); rect(14, 3, 7, 7); rect(3, 14, 7, 7); rect(14, 14, 7, 7)
        case "info.circle":
            oval(3, 3, 18, 18); oval(11.3, 7, 1.4, 1.4); move(12, 11); line(12, 17)
        case "wrench.and.screwdriver":
            move(4, 19); line(14, 9); curve(15, 3, 12, 5, 13, 3); line(16, 7); line(20, 8)
            line(21, 4); curve(19, 11, 23, 7, 22, 10); line(8, 22); line(4, 19); p.closeSubpath()
            move(3, 3); line(11, 11); move(14, 14); line(21, 21)
        default: return nil
        }
        return p
    }
}

// Dashboard pictograms: consistent thin outline treatment matching the reference.
struct DashboardMetricIcon: View {
    let symbol: String
    var body: some View {
        ReferencePictogram(symbol: symbol, size: 21)
            .foregroundStyle(Color.appMuted)
            .frame(width: 24, height: 25)
            .accessibilityHidden(true)
    }
}

// MARK: - Metric rows and tiles

struct MetricRow: View {
    private let valueFontSize: CGFloat = 21
    let icon: String
    let title: String
    let value: String
    var unit: String? = nil
    var detail: String? = nil
    var detailColor: Color = .appMuted
    var trendUp: Bool? = nil
    var trendFavourable: Bool? = nil

    var body: some View {
        HStack(spacing: 10) {
            DashboardMetricIcon(symbol: icon)
            Text(title.uppercased())
                .font(StrapTypography.body(12.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.appFG)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(StrapTypography.metric(valueFontSize, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.appFG)
                    if let unit {
                        Text(unit)
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appMuted)
                    }
                    if let trendUp, let trendFavourable {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 7, weight: .bold))
                            .rotationEffect(.degrees(trendUp ? 0 : 180))
                            .foregroundStyle(trendFavourable ? Color.appGood : Color.appWarn)
                            .accessibilityLabel(trendFavourable ? "Favourable trend" : "Unfavourable trend")
                    }
                }
                if let detail {
                    Text(detail)
                        .font(StrapTypography.metric(12, weight: .regular))
                        .foregroundStyle(detailColor)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: 95, alignment: .trailing)
                }
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, AppLayout.cardInset)
        .frame(minHeight: AppLayout.dashboardRowHeight)
        .background(RoundedRectangle(cornerRadius: AppLayout.dashboardRowRadius).fill(LinearGradient.dashboardCard))
        .overlay(RoundedRectangle(cornerRadius: AppLayout.dashboardRowRadius).strokeBorder(Color.appLine.opacity(0.25), lineWidth: 0.5))
        .padding(.bottom, AppLayout.dashboardRowSpacing)
        .accessibilityElement(children: .combine)
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    let chip: String
    var chipGood: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(StrapTypography.body(10, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Color.appMuted)
                .frame(minHeight: 27, alignment: .topLeading)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(StrapTypography.metric(25, weight: .bold))
                    .foregroundStyle(Color.appFG)
                if let unit {
                    Text(unit)
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                }
            }
            Text(chip)
                .font(StrapTypography.body(10))
                .foregroundStyle(chipGood ? Color.appGood : Color.appMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(chipGood ? Color.appGoodChipBG : Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(chipGood ? Color.appGood : Color.appLine, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient.appCard))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(StrapTypography.body(9.5, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(Color.appMuted)
            Text(value)
                .font(StrapTypography.metric(20, weight: .bold))
                .foregroundStyle(Color.appFG)
            if let detail {
                Text(detail)
                    .font(StrapTypography.body(9.5))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient.appCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Pickers

/// Chip-style exclusive picker (mockup rm-seg). `selection == nil` = nothing picked.
struct ChipPicker<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(StrapTypography.body(11.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9).fill(selection == option ? Color.appSurface : Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selection == option ? Color.appAccent : Color.appLine, lineWidth: 1))
                        .foregroundStyle(selection == option ? Color.appAccent : Color.appMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct YesNoRow: View {
    let question: String
    @Binding var value: Bool
    var showTopBorder: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(question)
                .font(StrapTypography.body(12.5))
                .foregroundStyle(Color.appFG)
            Spacer()
            HStack(spacing: 4) {
                yesNoButton("Yes", isOn: value) { value = true }
                yesNoButton("No", isOn: !value) { value = false }
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            if showTopBorder {
                Rectangle().fill(Color.appLine).frame(height: 1)
            }
        }
    }

    private func yesNoButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(StrapTypography.body(11, weight: .medium))
                .frame(minWidth: 44, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? Color.appSurface : Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isOn ? Color.appAccent : Color.appLine, lineWidth: 1))
                .foregroundStyle(isOn ? Color.appAccent : Color.appMuted)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stress gauge (0â€“3 semicircle)

struct StressGauge: View {
    /// nil == unavailable (no baseline): arcs only, no needle.
    let value: Double?

    private let cx: CGFloat = 115
    private let cy: CGFloat = 100
    private let radius: CGFloat = 80

    var body: some View {
        ZStack {
            arc(180, 240)
                .stroke(Color(hex: 0x00E676), style: StrokeStyle(lineWidth: 11, lineCap: .round))
            arc(240, 300)
                .stroke(Color(hex: 0xFFDE00), lineWidth: 11)
            arc(300, 360)
                .stroke(Color(hex: 0xFF3B30), style: StrokeStyle(lineWidth: 11, lineCap: .round))
            if let value {
                let angle = (180.0 + min(max(value, 0), 3) / 3.0 * 180.0) * .pi / 180.0
                Path { p in
                    p.move(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: cx + 68 * cos(angle), y: cy + 68 * sin(angle)))
                }
                .stroke(Color.appFG, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                Circle()
                    .fill(Color.appFG)
                    .frame(width: 10, height: 10)
                    .position(x: cx, y: cy)
            }
        }
        .frame(width: 230, height: 124)
    }

    private func arc(_ start: Double, _ end: Double) -> Path {
        Path { p in
            p.addArc(
                center: CGPoint(x: cx, y: cy),
                radius: radius,
                startAngle: .degrees(start),
                endAngle: .degrees(end),
                clockwise: false
            )
        }
    }
}

/// Each tab owns its navigation bar, so declare its purchased-font title in
/// SwiftUI rather than relying on UIKit appearance or the outer TabView.
private struct StrapTabTypography: ViewModifier {
    let title: String
    func body(content: Content) -> some View {
        content
            .font(StrapTypography.body(15))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title.uppercased())
                        .font(StrapTypography.body(12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.appFG)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

extension View {
    func strapTabTypography(_ title: String) -> some View {
        modifier(StrapTabTypography(title: title))
    }
}
