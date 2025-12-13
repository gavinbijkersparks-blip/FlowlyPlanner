import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChildProfile.name) private var profiles: [ChildProfile]
    @Query private var lessons: [Lesson]
    @Query private var homeworkTasks: [HomeworkTask]
    @Query private var exams: [ExamPreparation]
    @EnvironmentObject private var profileStore: ProfileSelectionStore
    @State private var name: String = ""
    @State private var selectedDays: Set<Weekday> = Set(Weekday.schoolDays)
    @State private var bedtime: Date = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var maxMinutes: Int = 90
    @State private var saveError: String?
    @State private var selectedProfileID: PersistentIdentifier?
    @State private var statusMessage: String?
    @State private var didMigrate = false
    @State private var pendingDelete: ChildProfile?

    var body: some View {
        Form {
            if !profiles.isEmpty {
                Section(header: Text("Bestaande profielen")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(profiles) { profile in
                                profileCard(profile)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }
                    Text("Tik op een avatar om van kind te wisselen. Gebruik rechtsboven 'Nieuw' om een nieuw profiel aan te maken.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            Section {
                Button("Bewaar", action: saveProfile)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let status = statusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Kindprofiel")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Nieuw", action: startNewProfile)
            }
        }
        .onAppear {
            loadProfileFromSelection(defaultFirst: true)
            migrateUnassignedToFirstProfile()
        }
        .onChange(of: profiles) { _, _ in alignSelectionWithProfiles() }
        .alert("Opslaan mislukt", isPresented: Binding(
            get: { saveError != nil },
            set: { _ in saveError = nil }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Probeer het later opnieuw.")
        }
        .alert("Profiel verwijderen?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Verwijder", role: .destructive) {
                if let profile = pendingDelete {
                    deleteProfile(profile)
                }
                pendingDelete = nil
            }
            Button("Annuleer", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            if let profile = pendingDelete {
                let label = profile.name.isEmpty ? "dit profiel" : profile.name
                Text("Weet je zeker dat je \(label) wilt verwijderen?")
            }
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
                profileStore.selectedProfileID = profile.persistentModelID
            } else {
                let newProfile = ChildProfile(
                    name: trimmedName,
                    schoolDays: days,
                    bedtime: bedtime,
                    maxStudyMinutesPerDay: maxMinutes
                )
                modelContext.insert(newProfile)
                selectedProfileID = newProfile.persistentModelID
                profileStore.selectedProfileID = newProfile.persistentModelID
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
            profileStore.selectedProfileID = id
            return
        }
        if defaultFirst, let first = profiles.first {
            selectedProfileID = first.persistentModelID
            profileStore.selectedProfileID = first.persistentModelID
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
        profileStore.selectedProfileID = nil
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

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if let first = parts.first?.first {
            if let last = parts.dropFirst().first?.first {
                return "\(first)\(last)"
            }
            return "\(first)"
        }
        return "?"
    }

    private func deleteProfile(_ profile: ChildProfile) {
        // Verwijder gekoppelde items
        lessons.filter { $0.profile?.persistentModelID == profile.persistentModelID }.forEach(modelContext.delete)
        homeworkTasks.filter { $0.profile?.persistentModelID == profile.persistentModelID }.forEach(modelContext.delete)
        exams.filter { $0.profile?.persistentModelID == profile.persistentModelID }.forEach(modelContext.delete)
        modelContext.delete(profile)
        do {
            try modelContext.save()
            // reset selectie
            selectedProfileID = profiles.first?.persistentModelID
            profileStore.selectedProfileID = selectedProfileID
            loadProfileFromSelection(defaultFirst: true)
        } catch {
            saveError = "Verwijderen mislukt: \(error.localizedDescription)"
        }
    }

    private func migrateUnassignedToFirstProfile() {
        guard !didMigrate, let first = profiles.first else { return }
        var changed = false
        for lesson in lessons where lesson.profile == nil {
            lesson.profile = first
            changed = true
        }
        for hw in homeworkTasks where hw.profile == nil {
            hw.profile = first
            changed = true
        }
        for exam in exams where exam.profile == nil {
            exam.profile = first
            changed = true
        }
        if selectedProfileID == nil {
            selectedProfileID = first.persistentModelID
            profileStore.selectedProfileID = first.persistentModelID
            fillFields(from: first)
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
        didMigrate = true
    }

    @ViewBuilder
    private func profileCard(_ profile: ChildProfile) -> some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.accentColor.opacity(selectedProfileID == profile.persistentModelID ? 0.35 : 0.18))
                    .overlay(
                        Circle()
                            .stroke(selectedProfileID == profile.persistentModelID ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Text(initials(for: profile.name))
                            .font(.headline)
                            .foregroundStyle(.primary)
                    )

                Button(role: .destructive) {
                    pendingDelete = profile
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                .offset(x: 10, y: -10)
            }

            Text(profile.name.isEmpty ? "Naamloos" : profile.name)
                .font(.subheadline)
                .lineLimit(1)
            if selectedProfileID == profile.persistentModelID {
                Text("Actief")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
        .frame(width: 110)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(selectedProfileID == profile.persistentModelID ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .onTapGesture {
            selectedProfileID = profile.persistentModelID
            profileStore.selectedProfileID = profile.persistentModelID
            loadProfileFromSelection(defaultFirst: false)
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(for: ChildProfile.self, inMemory: true)
}
