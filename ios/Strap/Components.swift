import SwiftUI
import CoreText


// MARK: - Typography
// Bundled Proxima Nova and DIN Pro; keep font weight explicit to avoid thin fallbacks.
enum StrapTypography {
    // Use the font's actual internal PostScript name, not its .ttf filename.
    // Some bundled Proxima faces have filenames that differ from UIFont names.
    private static let fontNames: [String: String] = {
        let files = ["ProximaNova-Regular", "ProximaNova-Bold", "ProximaNova-Light",
                     "ProximaNova-RegularIt", "ProximaNova-BoldIt", "ProximaNova-LightIt",
                     "proxima-nova-medium", "proxima-nova-semibold",
                     "DINPro-Regular", "DINPro-Light", "DINPro-Bold"]
        var names: [String: String] = [:]
        for file in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts")
                    ?? Bundle.main.url(forResource: file, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let descriptor = descriptors.first,
               let postScript = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                names[file] = postScript
            }
        }
        return names
    }()
    private static func bundled(_ file: String, size: CGFloat) -> Font? {
        guard let name = fontNames[file], UIFont(name: name, size: size) != nil else { return nil }
        return .custom(name, size: size)
    }

    private static func weightName(_ weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black { return "Bold" }
        // Use the bundled genuine Semibold and Medium faces for their requested weights.
        if weight == .semibold { return "Semibold" }
        if weight == .medium { return "Medium" }
        if weight == .light || weight == .ultraLight { return "Light" }
        return "Regular"
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let variant = weightName(weight)
        let file = variant == "Semibold" ? "proxima-nova-semibold"
                 : variant == "Medium" ? "proxima-nova-medium"
                 : "ProximaNova-\(variant)"
        return bundled(file, size: size) ?? .system(size: size, weight: weight)
    }

    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let file = "DINPro-\(weightName(weight))"
        return (bundled(file, size: size) ?? bundled("DINPro-Regular", size: size)
                ?? .system(size: size, weight: weight)).monospacedDigit()
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
        .background(
            LinearGradient(colors: [Color.appCanvasTop, Color.appBG],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
    }
}

struct DemoBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Design preview — sample data")
                .font(StrapTypography.body(12, weight: .semibold))
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

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppLayout.cardInset)
        .background(RoundedRectangle(cornerRadius: AppLayout.cardRadius).fill(LinearGradient.appCard))
        .overlay(RoundedRectangle(cornerRadius: AppLayout.cardRadius).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
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
                .font(StrapTypography.body(12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.appFG)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(StrapTypography.body(15))
                    .foregroundStyle(Color.appMuted)
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
            .font(StrapTypography.body(12, weight: .semibold))
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
    var lineWidth: CGFloat = 8
    var size: CGFloat = 96
    let centerText: String
    var centerFont: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.appLine, lineWidth: lineWidth)
            if let progress, progress > 0 {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(centerText)
                .font(StrapTypography.metric(centerFont, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .foregroundStyle(Color.appFG)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
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

/// Vertical bed→wake range bars on a shared time axis (0…axisMax). Each span
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

// Dashboard pictograms: consistent thin outline treatment matching the WHOOP reference.
struct DashboardMetricIcon: View {
    let symbol: String
    var body: some View {
        ZStack {
            if symbol == "heart.pulse" {
                Image(systemName: "heart")
                    .font(.system(size: 20, weight: .ultraLight))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .light))
                    .offset(x: 3, y: 1)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .ultraLight))
            }
        }
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
                .font(StrapTypography.body(12, weight: .semibold))
                .tracking(0.65)
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
        .frame(height: 64)
        .background(RoundedRectangle(cornerRadius: AppLayout.metricRadius).fill(LinearGradient.appCard))
        .overlay(RoundedRectangle(cornerRadius: AppLayout.metricRadius).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        .padding(.bottom, 11)
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
                    .font(StrapTypography.metric(25, weight: .medium))
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
                .font(StrapTypography.metric(20, weight: .medium))
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

// MARK: - Stress gauge (0–3 semicircle)

struct StressGauge: View {
    /// nil == unavailable (no baseline): arcs only, no needle.
    let value: Double?

    private let cx: CGFloat = 115
    private let cy: CGFloat = 100
    private let radius: CGFloat = 80

    var body: some View {
        ZStack {
            arc(180, 240)
                .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 11, lineCap: .round))
            arc(240, 300)
                .stroke(Color.appGood, lineWidth: 11)
            arc(300, 360)
                .stroke(Color.appWarn, style: StrokeStyle(lineWidth: 11, lineCap: .round))
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