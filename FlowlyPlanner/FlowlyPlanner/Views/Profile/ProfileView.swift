import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChildProfile.name) private var profiles: [ChildProfile]
    @State private var name: String = ""
    @State private var selectedDays: Set<Weekday> = Set(Weekday.schoolDays)
    @State private var bedtime: Date = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var maxMinutes: Int = 90
    @State private var saveError: String?
    @State private var selectedProfileID: PersistentIdentifier?
    @State private var statusMessage: String?

    var body: some View {
        Form {
            if !profiles.isEmpty {
                Section(header: Text("Bestaande profielen")) {
                    Picker("Selecteer", selection: $selectedProfileID) {
                        ForEach(profiles) { profile in
                            Text(profile.name.isEmpty ? "Naamloos" : profile.name)
                                .tag(profile.persistentModelID as PersistentIdentifier?)
                        }
                        Text("Nieuw profiel").tag(nil as PersistentIdentifier?)
                    }
                    .onChange(of: selectedProfileID) { _, newValue in
                        if newValue != nil {
                            loadProfileFromSelection(defaultFirst: false)
                        } else {
                            startNewProfile()
                        }
                    }
                }
            }
            Section(header: Text("Kindprofiel")) {
                TextField("Naam", text: $name)
                VStack(alignment: .leading) {
                    Text("Schooldagen")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                        ForEach(Weekday.allCases) { day in
                            Button {
                                toggle(day)
                            } label: {
                                Text(day.label)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(selectedDays.contains(day) ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                DatePicker("Bedtijd", selection: $bedtime, displayedComponents: .hourAndMinute)
                Stepper("Max studietijd per dag: \(maxMinutes) min", value: $maxMinutes, in: 30...240, step: 15)
            }
            Button("Bewaar", action: saveProfile)
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let status = statusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Kindprofiel")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Nieuw", action: startNewProfile)
            }
        }
        .onAppear { loadProfileFromSelection(defaultFirst: true) }
        .onChange(of: profiles) { _, _ in alignSelectionWithProfiles() }
        .alert("Opslaan mislukt", isPresented: Binding(
            get: { saveError != nil },
            set: { _ in saveError = nil }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Probeer het later opnieuw.")
        }
    }

    private func toggle(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }

    private func saveProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Naam is verplicht"
            return
        }

        let days = Array(selectedDays).sorted { $0.rawValue < $1.rawValue }
        do {
            if
                let id = selectedProfileID,
                let profile = profiles.first(where: { $0.persistentModelID == id })
            {
                profile.name = trimmedName
                profile.schoolDays = days
                profile.bedtime = bedtime
                profile.maxStudyMinutesPerDay = maxMinutes
                selectedProfileID = profile.persistentModelID
            } else {
                let newProfile = ChildProfile(
                    name: trimmedName,
                    schoolDays: days,
                    bedtime: bedtime,
                    maxStudyMinutesPerDay: maxMinutes
                )
                modelContext.insert(newProfile)
                selectedProfileID = newProfile.persistentModelID
            }
            try modelContext.save()
            statusMessage = "Opgeslagen"
        } catch {
            saveError = error.localizedDescription
            statusMessage = nil
        }
    }

    private func loadProfileFromSelection(defaultFirst: Bool) {
        if let id = selectedProfileID, let profile = profiles.first(where: { $0.persistentModelID == id }) {
            fillFields(from: profile)
            return
        }
        if defaultFirst, let first = profiles.first {
            selectedProfileID = first.persistentModelID
            fillFields(from: first)
        }
    }

    private func alignSelectionWithProfiles() {
        if let id = selectedProfileID, profiles.contains(where: { $0.persistentModelID == id }) {
            loadProfileFromSelection(defaultFirst: false)
        } else {
            startNewProfile()
        }
    }

    private func startNewProfile() {
        selectedProfileID = nil
        name = ""
        selectedDays = Set(Weekday.schoolDays)
        bedtime = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
        maxMinutes = 90
        statusMessage = nil
    }

    private func fillFields(from profile: ChildProfile) {
        name = profile.name
        selectedDays = Set(profile.schoolDays)
        bedtime = profile.bedtime
        maxMinutes = profile.maxStudyMinutesPerDay
        statusMessage = nil
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(for: ChildProfile.self, inMemory: true)
}
