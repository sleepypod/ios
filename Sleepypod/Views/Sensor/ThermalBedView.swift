import SceneKit
import SwiftUI
import UIKit

// MARK: - Card

/// Sensors card: a split-king bed in SceneKit with the six measured surface regions
/// (outer, center, inner per side) painted into the mattress covers on the shared
/// temperature ramp, so the bed and the Temp dial agree. Grey means missing or stale.
struct ThermalBedCard: View {
    @Environment(SensorStreamService.self) private var sensor
    @Environment(SettingsManager.self) private var settingsManager

    /// Readings older than this paint grey, matching sleepypod-core's THERMAL_STALE_SECONDS.
    static let staleSeconds: TimeInterval = 90

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let updatedAt = sensor.bedTempUpdatedAt
            let stale = updatedAt.map { context.date.timeIntervalSince($0) >= Self.staleSeconds } ?? true
            let left = ThermalZones.fahrenheit(sensor.leftTemps)
            let right = ThermalZones.fahrenheit(sensor.rightTemps)

            VStack(alignment: .leading, spacing: 10) {
                header(updatedAt: updatedAt, stale: stale, hasData: sensor.leftTemps != nil || sensor.rightTemps != nil)

                ThermalBedSceneView(
                    left: stale ? ThermalZones.none : left,
                    right: stale ? ThermalZones.none : right
                )
                .frame(height: 210)
                .allowsHitTesting(false)
                .accessibilityLabel("Thermal bed")

                cells(left: left, right: right, stale: stale)
                legend
            }
        }
        .cardStyle()
    }

    private func header(updatedAt: Date?, stale: Bool, hasData: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 10))
                .foregroundColor(Theme.amber)
            Text("THERMAL BED")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)
            if hasData && stale {
                Text("Stale")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.textMuted.opacity(0.15))
                    .clipShape(Capsule())
            }
            Spacer()
            if let updatedAt {
                Text(TempScreen.relativeTime(from: updatedAt))
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textMuted)
            }
        }
    }

    /// Six cells across the bed as seen: left outer → left inner, right inner → right outer.
    private func cells(left: [Double?], right: [Double?], stale: Bool) -> some View {
        let values = left + right.reversed()
        let labels = ["L out", "L ctr", "L in", "R in", "R ctr", "R out"]
        return HStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { i in
                let f = values[i]
                VStack(spacing: 3) {
                    Text(f.map { TemperatureConversion.displayTemp(Int($0.rounded()), format: settingsManager.temperatureFormat) } ?? "--")
                        .font(.system(size: 11, weight: .medium).monospaced())
                        .foregroundColor(f == nil ? Theme.textMuted : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(TempRamp.color(stale ? nil : f).opacity(f == nil ? 0.25 : 0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text(labels[i])
                        .font(.system(size: 8))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
    }

    private var legend: some View {
        let format = settingsManager.temperatureFormat
        let stops = TempRamp.stops.map { TempRamp.color($0.f) }
        return HStack(spacing: 8) {
            Text(TemperatureConversion.displayTemp(Int(TempRamp.minF), format: format))
            LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
                .frame(height: 5)
                .clipShape(Capsule())
            Text(TemperatureConversion.displayTemp(Int(TempRamp.maxF), format: format))
        }
        .font(.system(size: 9).monospaced())
        .foregroundColor(Theme.textMuted)
    }
}

// MARK: - Zones

enum ThermalZones {
    static let none: [Double?] = [nil, nil, nil]

    /// OUTER, CENTER, INNER surface readings in °F; nil when the sensor reports nothing.
    static func fahrenheit(_ side: BedTempSide?) -> [Double?] {
        (0..<3).map { i in
            guard let c = side?.temps[safe: i], c > -100, c.isFinite else { return nil }
            return Double(c) * 9 / 5 + 32
        }
    }
}

// MARK: - Heat Texture

/// The heat painted into a mattress cover: a field across the mattress's width through its
/// three zone readings on the shared ramp, a soft fall-off at head and foot, and a fine knit.
/// Repainted only when its key changes.
enum HeatTexture {
    /// Across-width × head-to-foot, in points.
    static let size = CGSize(width: 96, height: 200)
    /// The cover's own grey; a missing zone shows the cover.
    static let cover: (r: Double, g: Double, b: Double) = (0x8d / 255.0, 0x91 / 255.0, 0x99 / 255.0)
    /// How strongly a reading tints the cover.
    static let tint = 0.85

    /// Repaint only when a reading moves by half a degree or appears/disappears.
    static func key(_ zones: [Double?]) -> String {
        zones.map { $0.map { String(($0 * 2).rounded() / 2) } ?? "x" }.joined(separator: ",")
    }

    /// Colour of each zone, OUTER / CENTER / INNER, blended over the cover.
    static func zoneColors(_ zones: [Double?]) -> [(r: Double, g: Double, b: Double)] {
        zones.map { f in
            guard let f else { return cover }
            let c = TempRamp.rgb(f)
            return (cover.r + (c.r - cover.r) * tint, cover.g + (c.g - cover.g) * tint, cover.b + (c.b - cover.b) * tint)
        }
    }

    static func paint(_ zones: [Double?], outerOnLeft: Bool) -> UIImage {
        let colors = zoneColors(zones)
        let ordered = outerOnLeft ? colors : colors.reversed()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let cgColors = [ordered[0], ordered[0], ordered[1], ordered[2], ordered[2]].map {
                CGColor(red: $0.r, green: $0.g, blue: $0.b, alpha: 1)
            }
            if let field = CGGradient(colorsSpace: space, colors: cgColors as CFArray, locations: [0, 1.0 / 6, 0.5, 5.0 / 6, 1]) {
                cg.drawLinearGradient(field, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            }

            // Head and foot fall off slightly so the cover reads as a soft surface
            let shade = [CGColor(gray: 0, alpha: 0.14), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.14)]
            if let falloff = CGGradient(colorsSpace: space, colors: shade as CFArray, locations: [0, 0.18, 0.82, 1]) {
                cg.drawLinearGradient(falloff, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }

            // Knit: a faint dark rib row and a pale row every 2 pt
            for y in stride(from: 0.0, to: size.height, by: 2) {
                cg.setFillColor(CGColor(gray: 0, alpha: 0.05))
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: 0.5))
                cg.setFillColor(CGColor(gray: 1, alpha: 0.03))
                cg.fill(CGRect(x: 0, y: y + 0.5, width: size.width, height: 0.5))
            }
        }
    }
}

// MARK: - Scene

/// Split-king bed on a recessed plinth, viewed from the foot. The left sleeper's mattress
/// is on screen-left, matching the rest of the app. The view only redraws when a
/// mattress texture changes.
struct ThermalBedSceneView: UIViewRepresentable {
    let left: [Double?]
    let right: [Double?]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        view.isUserInteractionEnabled = false
        context.coordinator.update(left: left, right: right)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(left: left, right: right)
    }

    @MainActor
    final class Coordinator {
        let scene = SCNScene()
        let camera = SCNNode()
        private let leftCover = SCNMaterial()
        private let rightCover = SCNMaterial()
        private var leftKey: String?
        private var rightKey: String?

        // World units are roughly metres: two 0.95 × 2.0 mattresses make a king.
        private static let mattress = (width: 0.95, length: 2.0, height: 0.26, chamfer: 0.05)
        private static let seam = 0.015

        init() {
            build()
        }

        func update(left: [Double?], right: [Double?]) {
            let l = HeatTexture.key(left)
            if l != leftKey {
                leftKey = l
                leftCover.diffuse.contents = HeatTexture.paint(left, outerOnLeft: true)
            }
            let r = HeatTexture.key(right)
            if r != rightKey {
                rightKey = r
                rightCover.diffuse.contents = HeatTexture.paint(right, outerOnLeft: false)
            }
        }

        private func build() {
            let m = Self.mattress
            let root = scene.rootNode

            let plinth = box(width: 2 * m.width - 0.2, height: 0.1, length: m.length - 0.15, chamfer: 0.01, color: UIColor(hex: 0x8e8172))
            plinth.position = SCNVector3(0, 0.05, 0)
            root.addChildNode(plinth)

            let frameWidth = 2 * m.width + Self.seam + 0.08
            let frame = box(width: frameWidth, height: 0.16, length: m.length + 0.08, chamfer: 0.03, color: UIColor(hex: 0x2a2a2f))
            frame.position = SCNVector3(0, 0.18, 0)
            root.addChildNode(frame)

            let mattressY = 0.26 + m.height / 2
            let topY = 0.26 + m.height
            for (sign, cover) in [(-1.0, leftCover), (1.0, rightCover)] {
                let x = sign * (m.width + Self.seam) / 2

                let body = box(width: m.width, height: m.height, length: m.length, chamfer: m.chamfer, color: UIColor(hex: 0x8d9199))
                body.position = SCNVector3(x, mattressY, 0)
                root.addChildNode(body)

                // The heat sits on the flat of the cover, inside the rounded edge
                cover.lightingModel = .lambert
                cover.diffuse.wrapS = .clamp
                cover.diffuse.wrapT = .clamp
                cover.diffuse.mipFilter = .linear
                let plane = SCNPlane(width: m.width - 2 * m.chamfer, height: m.length - 2 * m.chamfer)
                plane.materials = [cover]
                let top = SCNNode(geometry: plane)
                top.eulerAngles.x = -.pi / 2
                top.position = SCNVector3(x, topY + 0.001, 0)
                root.addChildNode(top)

                let pillow = box(width: m.width - 0.3, height: 0.1, length: 0.3, chamfer: 0.045, color: UIColor(hex: 0xc9ccd2))
                pillow.position = SCNVector3(x, topY + 0.04, -m.length / 2 + 0.24)
                root.addChildNode(pillow)
            }

            let floor = SCNFloor()
            floor.reflectivity = 0
            let shadowOnly = SCNMaterial()
            shadowOnly.lightingModel = .shadowOnly
            floor.materials = [shadowOnly]
            root.addChildNode(SCNNode(geometry: floor))

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 320
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            root.addChildNode(ambientNode)

            let key = SCNLight()
            key.type = .directional
            key.intensity = 720
            key.castsShadow = true
            key.shadowMode = .deferred
            key.shadowRadius = 10
            key.shadowSampleCount = 16
            key.shadowColor = UIColor.black.withAlphaComponent(0.55)
            let keyNode = SCNNode()
            keyNode.light = key
            keyNode.eulerAngles = SCNVector3(-1.15, -0.35, 0)
            root.addChildNode(keyNode)

            let lens = SCNCamera()
            lens.fieldOfView = 25
            lens.zNear = 0.1
            lens.zFar = 50
            camera.camera = lens
            camera.position = SCNVector3(0, 2.6, 3.2)
            camera.look(at: SCNVector3(0, 0.3, 0.1))
            root.addChildNode(camera)
        }

        private func box(width: Double, height: Double, length: Double, chamfer: Double, color: UIColor) -> SCNNode {
            let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: chamfer)
            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.diffuse.contents = color
            geometry.materials = [material]
            return SCNNode(geometry: geometry)
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
