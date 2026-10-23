import SwiftUI

@main
struct SleepypodWatchApp: App {
    @State private var controller = RecordingController()

    var body: some Scene {
        WindowGroup {
            RecorderView().environment(controller)
        }
    }
}

struct RecorderView: View {
    @Environment(RecordingController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("sleepypod").font(.headline)
                Text("Records wrist movement overnight as labels for the movement classifier. It stays on this Watch until you send it.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !controller.availability.isEmpty {
                    Text(controller.availability).font(.footnote).foregroundStyle(.orange)
                }
                Stepper(value: $controller.hours, in: 1...12, step: 0.5) {
                    Text("\(controller.hours.formatted(.number.precision(.fractionLength(1)))) h")
                }
                Button("Record tonight") { controller.recordTonight() }
                    .disabled(!controller.availability.isEmpty && controller.availability.hasPrefix("Recording isn't"))
                Toggle("Include raw 50 Hz", isOn: $controller.includeRaw).font(.footnote)
                Button(controller.busy ? "Sending…" : "Send to iPhone") {
                    Task { await controller.send() }
                }
                .disabled(controller.busy || controller.plan == nil)
                if !controller.status.isEmpty {
                    Text(controller.status).font(.footnote)
                }
            }
        }
    }
}
