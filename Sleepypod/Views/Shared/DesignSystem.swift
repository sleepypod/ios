import SwiftUI

extension Font {
    static func monoPostScriptName(weight: Font.Weight) -> String {
        weight == .light ? "IBMPlexMono-Light" : weight == .regular ? "IBMPlexMono" : "IBMPlexMono-Medm"
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(monoPostScriptName(weight: weight), size: size, relativeTo: style)
    }
}

/// Mono eyebrow label. Text is rendered verbatim so mixed-case values ("8h 30m", "iPHONE") survive;
/// callers pass the uppercase label.
struct Eyebrow: View {
    let text: String
    var size: CGFloat = 11
    var color = Theme.text2
    init(_ text: String, size: CGFloat = 11, color: Color = Theme.text2) {
        self.text = text; self.size = size; self.color = color
    }
    var body: some View {
        Text(text).font(.mono(size, relativeTo: .caption2)).tracking(size * 0.08).foregroundStyle(color)
    }
}

struct StatusDot: View {
    var color = Theme.green
    var size: CGFloat = 6
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// The rounded square used beside the Sleepypod wordmark in the design source.
struct PodMark: View {
    var size: CGFloat = 48
    var discovery = false

    var body: some View {
        RoundedRectangle(cornerRadius: discovery ? 5 : 3)
            .fill(Theme.text1)
            .frame(width: discovery ? 22 : 14, height: discovery ? 22 : 14)
            .frame(width: size, height: size)
            .background(discovery ? Theme.card : Theme.active, in: RoundedRectangle(cornerRadius: discovery ? 24 : 13, style: .continuous))
            .overlay {
                if discovery { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border2, lineWidth: 1) }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Chrome (Liquid Glass, with an opaque fallback for Reduce Transparency)

struct ChromeSurface<S: Shape>: ViewModifier {
    let shape: S
    var interactive = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.card, in: shape)
                .overlay(shape.stroke(Theme.border1, lineWidth: 1))
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

/// Selected/raised fill used inside glass sheets (`--glassSel` in the source).
enum GlassFill {
    static func selected(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.06)
    }
    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }
}

/// Primary-button label that swaps to a spinner and progress text while work runs.
struct BusyLabel: View {
    let title: String
    let busyTitle: String
    let isBusy: Bool

    var body: some View {
        if isBusy {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.background)
                Text(busyTitle)
            }
        } else {
            Text(title)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Theme.background).background(Theme.text1, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Theme.text1)
            .chromeSurface()
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// 44pt round glass toolbar-style button used outside a navigation bar (onboarding back).
struct GlassCircleButton: View {
    let title: String
    let systemImage: String
    var size: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.text1)
                .frame(width: size, height: size)
                .chromeSurface(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct SettingsToolbar: ViewModifier {
    @State private var presented = ["settings", "allsettings"].contains(DebugRoute.current)
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { presented = true }
            }
        }
        .sheet(isPresented: $presented) { SettingsSheet() }
    }
}

extension View {
    func chromeSurface() -> some View { modifier(ChromeSurface(shape: Capsule())) }
    func chromeSurface<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        modifier(ChromeSurface(shape: shape, interactive: interactive))
    }
    func settingsToolbar() -> some View { modifier(SettingsToolbar()) }
}

// MARK: - Segmented control

/// The source's segmented switcher: `active` track, 3pt inset, `card` thumb with a soft shadow.
struct SegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        var systemImage: String?
        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value
    var onSelect: ((Value) -> Void)?
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let selected = segment.value == selection
                Button {
                    guard !selected else { return }
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.25)) { selection = segment.value }
                    onSelect?(segment.value)
                } label: {
                    HStack(spacing: 5) {
                        if let image = segment.systemImage {
                            Image(systemName: image).font(.system(size: 12, weight: .semibold))
                        }
                        Text(segment.title).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? Theme.text1 : Theme.text2)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background {
                        if selected {
                            Capsule().fill(Theme.card)
                                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.active, in: Capsule())
    }
}

// MARK: - Cards and grouped rows

struct CardStyle: ViewModifier {
    var radius: CGFloat = 22
    var vertical: CGFloat = 16
    var horizontal: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(.vertical, vertical)
            .padding(.horizontal, horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: radius)
    }
}

extension View {
    func cardStyle(radius: CGFloat = 22, vertical: CGFloat = 16, horizontal: CGFloat = 18) -> some View {
        modifier(CardStyle(radius: radius, vertical: vertical, horizontal: horizontal))
    }

    func cardSurface(radius: CGFloat = 22, fill: Color = Theme.card, border: Color = Theme.border1) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(border, lineWidth: 1))
    }
}

/// Inset-grouped card whose children are separated by full-width 1pt hairlines.
struct GroupedCard<Content: View>: View {
    var glass = false
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let divider = glass ? GlassFill.border(scheme) : Theme.border1
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    if index > 0 { Rectangle().fill(divider).frame(height: 1) }
                    subviews[index]
                }
            }
        }
        .modifier(GroupedCardSurface(glass: glass))
    }
}

private struct GroupedCardSurface: ViewModifier {
    let glass: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if glass && !reduceTransparency {
            content.background(GlassFill.selected(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            content.cardSurface()
        }
    }
}

/// Section eyebrow above a grouped card (`BED`, `HEALTH`, `WRITE`).
struct GroupedSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title).padding(.leading, 16).accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// A grouped-list row. `tile` draws the 30pt neutral icon tile used in full Settings; otherwise the
/// glyph sits bare, as in the gear sheet and analysis card.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var iconColor: Color = Theme.icon
    var tile = false
    var chevron = false
    var height: CGFloat = 50
    var titleFont: Font = .callout
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                if tile {
                    Image(systemName: icon).font(.system(size: 15)).foregroundStyle(iconColor)
                        .frame(width: 30, height: 30)
                        .background(Theme.active, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(iconColor).frame(width: 22)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(titleFont).foregroundStyle(Theme.text1)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.text2) }
            }
            Spacer(minLength: 8)
            trailing
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text3)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: height)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, icon: String? = nil, iconColor: Color = Theme.icon,
         tile: Bool = false, chevron: Bool = false, height: CGFloat = 50, titleFont: Font = .callout) {
        self.init(title: title, subtitle: subtitle, icon: icon, iconColor: iconColor, tile: tile, chevron: chevron,
                  height: height, titleFont: titleFont) { EmptyView() }
    }
}

extension SettingsRow {
    init(_ title: String, subtitle: String? = nil, icon: String? = nil, iconColor: Color = Theme.icon,
         tile: Bool = false, chevron: Bool = false, height: CGFloat = 50, titleFont: Font = .callout,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, icon: icon, iconColor: iconColor, tile: tile, chevron: chevron,
                  height: height, titleFont: titleFont, trailing: trailing)
    }
}

/// Trailing value text: SF in `text2` for words ("On", "Jon · Heidi"), mono for figures.
struct RowValue: View {
    let text: String
    var mono = false
    var color = Theme.text2
    init(_ text: String, mono: Bool = false, color: Color = Theme.text2) {
        self.text = text; self.mono = mono; self.color = color
    }
    var body: some View {
        Text(text).font(mono ? .mono(12, relativeTo: .caption) : .subheadline).foregroundStyle(color).lineLimit(1)
    }
}

// MARK: - Formatting

enum DisplayTime {
    static func minutes(_ value: String) -> Int {
        let p = value.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }
    static func clock(_ value: String) -> String {
        clock(minutes: minutes(value))
    }
    static func clock(minutes m: Int) -> String {
        let m = (m % 1440 + 1440) % 1440
        return "\((m / 60 + 11) % 12 + 1):\(String(format: "%02d", m % 60)) \(m < 720 ? "AM" : "PM")"
    }
    /// Axis tick: drops ":00" on the hour ("2 AM", "10:30 PM").
    static func tick(minutes m: Int) -> String {
        let m = (m % 1440 + 1440) % 1440
        let hour = (m / 60 + 11) % 12 + 1
        let period = m < 720 ? "AM" : "PM"
        return m % 60 == 0 ? "\(hour) \(period)" : "\(hour):\(String(format: "%02d", m % 60)) \(period)"
    }
    static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }
}
