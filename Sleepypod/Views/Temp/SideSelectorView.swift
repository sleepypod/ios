import SwiftUI

struct SideSelectorView: View {
    @Environment(DeviceManager.self) private var device
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        SegmentedControl(
            segments: [
                .init(value: SideSelection.left, title: settings.leftName),
                .init(value: .both, title: "Both", systemImage: "link"),
                .init(value: .right, title: settings.rightName)
            ],
            selection: Binding(
                get: { device.isLinked ? .both : device.selectedSide },
                set: { selection in
                    if (selection == .both) != device.isLinked { device.toggleLink() }
                    device.selectSide(selection)
                }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bed side")
    }
}
