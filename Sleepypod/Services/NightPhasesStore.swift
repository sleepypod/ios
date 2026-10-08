import Foundation
import Observation

/// Tonight's Night / Dawn temperatures per side, editable from the stepper. The phase split and the
/// schedule writes live on the pod (`schedules.getNightPhases` / `setNightPhase`); this only batches
/// taps and shows optimistic values, like the web's useNightPhases.
@MainActor
@Observable
final class NightPhasesStore {
    private(set) var phases: [Side: NightPhases] = [:]
    private(set) var error: String?
    /// The pod's sleepypod-core predates the Night / Dawn endpoints.
    private(set) var unsupported = false
    private(set) var isLoading = false
    private var pending: [Side: [NightPhaseKey: Int]] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var lastWrite: [Side: Task<Void, Never>] = [:]

    /// Taps within this window batch into one schedule write.
    private let commitDelay: Duration = .milliseconds(700)
    private var api: SleepypodProtocol { APIBackend.current.createClient() }

    func load(_ sides: [Side]) async {
        isLoading = phases.isEmpty
        defer { isLoading = false }
        for side in sides {
            do {
                if let result = try await api.getNightPhases(side: side) { phases[side] = result } else { phases[side] = nil }
                unsupported = false
                error = nil
            } catch {
                handle(error, loading: true)
            }
        }
    }

    func value(_ side: Side, _ phase: NightPhaseKey) -> Int? {
        if let optimistic = pending[side]?[phase] { return optimistic }
        return phases[side]?.phase(phase).map { Int($0.temperatureF.rounded()) }
    }

    /// ± one display step on a phase for each side (both when linked); writes after a short pause.
    func nudge(_ sides: [Side], phase: NightPhaseKey, delta: Int, format: TemperatureFormat) {
        for side in sides {
            guard let base = value(side, phase) else { continue }
            let next = Self.step(base, delta: delta, format: format)
            pending[side, default: [:]][phase] = next
            let key = "\(side.rawValue)-\(phase.rawValue)"
            timers[key]?.cancel()
            timers[key] = Task { [weak self] in
                do { try await Task.sleep(for: self?.commitDelay ?? .zero) } catch { return }
                await self?.commit(side: side, phase: phase, target: next)
            }
        }
    }

    /// One display degree: whole °C in Celsius, otherwise 1°F. Clamped to the pod's 55–110°F.
    static func step(_ tempF: Int, delta: Int, format: TemperatureFormat) -> Int {
        let next = format == .celsius
            ? TemperatureConversion.tempCToF((TemperatureConversion.tempFToC(tempF)).rounded() + Double(delta))
            : tempF + delta
        return min(TemperatureConversion.maxTempF, max(TemperatureConversion.minTempF, next))
    }

    private func commit(side: Side, phase: NightPhaseKey, target: Int) async {
        let previous = lastWrite[side]
        let write = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let result = try await self.api.setNightPhase(side: side, phase: phase, temperatureF: target)
                self.phases[side] = result
                self.error = nil
            } catch {
                self.handle(error, loading: false)
            }
            if self.pending[side]?[phase] == target { self.pending[side]?[phase] = nil }
        }
        lastWrite[side] = write
        await write.value
    }

    /// A 404 on the read means the procedure doesn't exist on this pod's sleepypod-core.
    private func handle(_ error: Error, loading: Bool) {
        let missingProcedure: Bool = if case APIError.invalidResponse(statusCode: 404) = error { loading } else { false }
        if (error as? URLError)?.code == .unsupportedURL || missingProcedure {
            unsupported = true
            self.error = "Update sleepypod on the pod to edit Night & Dawn"
        } else {
            self.error = error.localizedDescription
        }
    }
}
