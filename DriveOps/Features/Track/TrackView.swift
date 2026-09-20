import SwiftUI
import SwiftOBD2

struct TrackView: View {
    @ObservedObject var vm: OBDViewModel
    @StateObject private var session = TrackSession()
    @State private var showingTrack = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "flag.checkered").font(.system(size: 64)).foregroundStyle(.yellow)
                Text("Built for a quick glance").font(.title2.bold())
                Text("A full-screen instrument panel. Rotate your phone horizontally, then long-press any sensor to change it.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Enter Track", systemImage: "arrow.up.left.and.arrow.down.right") { showingTrack = true }
                    .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                Text("Manual lap timing · Tap Lap at the line")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black).preferredColorScheme(.dark)
            .navigationTitle("Track")
        }
        .fullScreenCover(isPresented: $showingTrack) {
            TrackPanel(vm: vm, session: session)
        }
    }
}

struct TrackPanel: View {
    @ObservedObject var vm: OBDViewModel
    @ObservedObject var session: TrackSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trackSensorSlots") private var savedSlots = "010D,0105,0111,0104"
    @AppStorage("trackColorScheme") private var colorSchemeRaw = TrackColorScheme.rainbow.rawValue
    @State private var editingSlot: Int?
    @State private var confirmReset = false
    private var scheme: TrackColorScheme { TrackColorScheme(rawValue: colorSchemeRaw) ?? .rainbow }
    private var slots: [String] {
        let ids = savedSlots.split(separator: ",").map(String.init)
        return ids.count == 4 && ids.allSatisfy({ PIDCatalog.command(named: $0) != nil }) ? ids : ["010D", "0105", "0111", "0104"]
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                VStack(spacing: 8) {
                    HStack {
                        Label("TRACK", systemImage: "flag.checkered").font(.headline)
                        Text(vm.activeConnectionType == .demo ? "DEMO" : vm.connectionState.isConnected ? "CONNECTED" : "OFFLINE")
                            .font(.caption.bold()).foregroundStyle(scheme.accent)
                        Spacer()
                        Button { dismiss() } label: { Label("Exit", systemImage: "xmark") }
                            .buttonStyle(.bordered).tint(.white)
                    }
                    revStrip(at: context.date)
                    if landscape {
                        HStack(spacing: 8) {
                            sensorColumn(indices: [0, 1], at: context.date)
                            timing.frame(maxWidth: .infinity)
                            sensorColumn(indices: [2, 3], at: context.date)
                        }.frame(maxHeight: .infinity)
                    } else {
                        Label("Rotate for the wide cockpit", systemImage: "iphone.gen3.radiowaves.left.and.right")
                            .font(.caption).foregroundStyle(.secondary)
                        timing
                        HStack(spacing: 8) {
                            sensorColumn(indices: [0, 1], at: context.date)
                            sensorColumn(indices: [2, 3], at: context.date)
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.ignoresSafeArea()).preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear { vm.setTrackDemand(Set(slots + ["010C"])) }
        .onChange(of: savedSlots) { _, _ in vm.setTrackDemand(Set(slots + ["010C"])) }
        .onDisappear { vm.setTrackDemand([]) }
        .sheet(isPresented: Binding(get: { editingSlot != nil }, set: { if !$0 { editingSlot = nil } })) {
            TrackFieldPicker(vm: vm, selected: editingSlot.map { slots[$0] } ?? "010D") { command in
                guard let index = editingSlot else { return }
                var updated = slots
                updated[index] = command
                savedSlots = updated.joined(separator: ",")
                editingSlot = nil
            }
        }
        .confirmationDialog("Reset all lap times?", isPresented: $confirmReset) {
            Button("Reset laps", role: .destructive) { session.reset() }
        }
    }

    private func reading(_ id: String, at date: Date) -> LiveMetric? {
        guard vm.connectionState.isConnected, let metric = vm.liveMetrics[id], metric.isUsable,
              date.timeIntervalSince(metric.updatedAt) <= 2 else { return nil }
        return metric
    }

    private func revStrip(at date: Date) -> some View {
        let rpm = reading("010C", at: date)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<24) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Double(index) < (rpm?.value ?? 0) / 8000 * 24 ? (index < 16 ? .green : index < 21 ? .yellow : .red) : Color.white.opacity(0.12))
                }
            }.frame(height: 12).accessibilityHidden(true)
            HStack {
                Text(rpm.map { MetricCatalog.format($0) } ?? "— rpm")
                Spacer()
                Text("SCALE 0–8,000 · NOT A REDLINE")
            }.font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.gray)
        }
    }

    private func sensorColumn(indices: [Int], at date: Date) -> some View {
        VStack(spacing: 8) {
            ForEach(indices, id: \.self) { index in
                let id = slots[index]
                let metric = reading(id, at: date)
                let color = scheme.fieldColor(index)
                VStack(alignment: .leading, spacing: 4) {
                    Text(PIDCatalog.command(named: id).map { MetricCatalog.displayName(for: $0).uppercased() } ?? id)
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.gray)
                    Text(metric.map { MetricCatalog.format($0) } ?? "—")
                        .font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.4).foregroundStyle(color)
                    if metric == nil { Text(vm.connectionState.isConnected ? "WAITING / NO FRESH DATA" : "OFFLINE").font(.system(size: 9)).foregroundStyle(.gray) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.5)))
                .contentShape(Rectangle())
                .onLongPressGesture { editingSlot = index }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("track-field-\(index)")
                .accessibilityHint("Long press to change sensor")
                .accessibilityAction(named: "Change sensor") { editingSlot = index }
            }
        }.frame(maxWidth: .infinity)
    }

    private var timing: some View {
        let color = scheme.timingColor
        return VStack(spacing: 6) {
            Text(session.isRunning ? "LAP \(session.laps.count + 1)" : "\(session.laps.count) LAPS COMPLETED")
                .font(.system(.headline, design: .monospaced)).foregroundStyle(color)
            Text(TrackSession.formatted(session.elapsed()))
                .font(.system(size: 42, weight: .heavy, design: .monospaced)).minimumScaleFactor(0.4).lineLimit(1)
            Divider()
            timeRow("LAST LAP", session.lastLap)
            timeRow("BEST LAP", session.bestLap)
            HStack(spacing: 8) {
                if session.isRunning {
                    Button("Stop") { session.stop() }.buttonStyle(.bordered)
                    Button("LAP", systemImage: "flag.checkered") { session.lap() }
                        .buttonStyle(.borderedProminent).tint(color).foregroundStyle(.black)
                } else {
                    Button("Reset") { confirmReset = true }.buttonStyle(.bordered).disabled(session.laps.isEmpty)
                    Button("START", systemImage: "play.fill") { session.start() }
                        .buttonStyle(.borderedProminent).tint(color).foregroundStyle(.black)
                }
            }.controlSize(.large).padding(.top, 4)
        }.padding(12).frame(maxHeight: .infinity)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.5)))
    }

    private func timeRow(_ name: String, _ value: TimeInterval?) -> some View {
        HStack {
            Text(name).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.gray)
            Spacer(minLength: 4)
            Text(TrackSession.formatted(value)).font(.system(.subheadline, design: .monospaced).bold())
        }
    }
}

private struct TrackFieldPicker: View {
    @ObservedObject var vm: OBDViewModel
    let selected: String
    let select: (String) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    private let suggestions = ["010D", "010C", "0105", "0111", "0104", "010F", "0110", "0142"]
    var body: some View {
        NavigationStack {
            List {
                Section("Suggested for Track") {
                    ForEach(suggestions.compactMap { PIDCatalog.command(named: $0) }.filter(matches), id: \.self) { row($0) }
                }
                Section("All sensors") {
                    ForEach(PIDCatalog.allLivePIDs.filter { !suggestions.contains($0.properties.command) && matches($0) }, id: \.self) { row($0) }
                }
            }
            .navigationTitle("Change field").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Name or PID")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func matches(_ pid: OBDCommand) -> Bool {
        search.isEmpty || (MetricCatalog.displayName(for: pid) + pid.properties.command).localizedCaseInsensitiveContains(search)
    }
    private func row(_ pid: OBDCommand) -> some View {
        Button { select(pid.properties.command) } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(MetricCatalog.displayName(for: pid))
                    Text(vm.obdInfo?.supportedPIDs?.contains(pid) == true ? "Reported supported" : "Availability not confirmed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected == pid.properties.command { Image(systemName: "checkmark") }
            }
        }.tint(.primary)
    }
}

#if DEBUG
#Preview("Track · landscape", traits: .landscapeLeft) {
    TrackPanel(vm: .stub(state: .connectedToVehicle, liveData: ["Engine RPM": "6250 rpm", "Vehicle Speed": "148 km/h", "Coolant Temperature": "92 °C", "Throttle Position": "81 %", "Engine Load": "76 %"]), session: TrackSession())
}
#Preview("Track · offline") { TrackView(vm: .stub(state: .disconnected)) }
#endif
