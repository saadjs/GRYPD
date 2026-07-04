import SwiftUI

struct SettingsView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.modelContext) private var context
    @AppStorage("defaultUnit") private var defaultUnitRaw = WeightUnit.lb.rawValue
    @AppStorage(DumbbellDefaults.keyLight) private var dumbbellLight = DumbbellDefaults.defaultLight
    @AppStorage(DumbbellDefaults.keyMedium) private var dumbbellMedium = DumbbellDefaults.defaultMedium
    @AppStorage(DumbbellDefaults.keyHeavy) private var dumbbellHeavy = DumbbellDefaults.defaultHeavy

    private var defaultUnit: WeightUnit { WeightUnit(rawValue: defaultUnitRaw) ?? .lb }

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Default weight unit", selection: $defaultUnitRaw) {
                        ForEach(WeightUnit.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                Section {
                    dumbbellPicker("Light", selection: $dumbbellLight)
                    dumbbellPicker("Medium", selection: $dumbbellMedium)
                    dumbbellPicker("Heavy", selection: $dumbbellHeavy)
                } header: {
                    Text("Default Dumbbells")
                } footer: {
                    Text("Auto-filled when logging based on the exercise.")
                }
                #if DEBUG
                Section {
                    Button("Seed sample history") {
                        SampleData.seed(context: context, catalog: catalog)
                    }
                    Button("Clear history", role: .destructive) {
                        SampleData.clear(context: context)
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug builds only. Seeding replaces existing logs with ~2 years of sample sessions across weighted, bodyweight, and timed moves.")
                }
                #endif

                Section {
                    VStack(spacing: 4) {
                        Text("GRYPD \(appVersion)")
                            .scaledFont(13, relativeTo: .caption)
                            .foregroundStyle(.secondary)
                        if let generatedText = catalogGeneratedText {
                            Text(generatedText)
                                .scaledFont(12, relativeTo: .caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: defaultUnitRaw) { oldRaw, newRaw in
                convertDumbbells(from: oldRaw, to: newRaw)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var catalogGeneratedText: String? {
        guard let generatedAt = catalog.generatedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Catalog updated \(formatter.string(from: generatedAt))"
    }

    private func dumbbellPicker(_ title: String, selection: Binding<Double>) -> some View {
        Picker(title, selection: selection) {
            ForEach(DumbbellDefaults.options(for: defaultUnit), id: \.self) { weight in
                Text(DumbbellDefaults.format(weight, unit: defaultUnit)).tag(weight)
            }
        }
    }

    /// Keep the stored dumbbell weights meaningful when the default unit flips:
    /// convert each to the new unit and snap to the nearest selectable option.
    private func convertDumbbells(from oldRaw: String, to newRaw: String) {
        guard let old = WeightUnit(rawValue: oldRaw),
              let new = WeightUnit(rawValue: newRaw), old != new else { return }
        for value in [$dumbbellLight, $dumbbellMedium, $dumbbellHeavy] {
            value.wrappedValue = DumbbellDefaults.nearestOption(
                old.convertedWeight(value.wrappedValue, to: new), for: new)
        }
    }
}
