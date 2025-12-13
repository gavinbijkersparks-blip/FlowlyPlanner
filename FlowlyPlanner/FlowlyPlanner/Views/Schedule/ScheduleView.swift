import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: ProfileSelectionStore
    @Query(sort: [SortDescriptor(\Lesson.weekday), SortDescriptor(\Lesson.startTime)]) private var lessons: [Lesson]
    @State private var showingAdd = false
    @State private var showingImport = false

    private var filteredLessons: [Lesson] {
        guard let id = profileStore.selectedProfileID else { return lessons }
        // Toon lessen van het actieve profiel + oude lessen zonder profiel-koppeling
        return lessons.filter { $0.profile?.persistentModelID == id || $0.profile == nil }
    }

    var body: some View {
        List {
            Section {
                if let profile = activeProfile() {
                    profileChip(profile)
                } else {
                    Text("Selecteer een profiel via het avatar-overzicht.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Weekday.allCases) { day in
                let dayLessons = filteredLessons.filter { $0.weekday == day.rawValue }
                Section(header: Text(day.label)) {
                    if dayLessons.isEmpty {
                        Text("Geen lessen")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dayLessons) { lesson in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                    .overlay(Image(systemName: "book.fill").foregroundStyle(.blue))
                                VStack(alignment: .leading) {
                                    Text(lesson.subject)
                                        .font(.headline)
                                    Text("\(timeString(lesson.startTime)) – \(timeString(lesson.endTime))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete { indices in
                            indices.map { dayLessons[$0] }.forEach(modelContext.delete)
                        }
                    }
                }
            }
        }
        .navigationTitle("Rooster")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: ProfileView()) {
                    Image(systemName: "person.crop.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingAdd = true }) {
                        Label("Nieuwe les", systemImage: "plus")
                    }
                    Button(action: { showingImport = true }) {
                        Label("Scan rooster", systemImage: "camera.viewfinder")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddLessonView()
        }
        .sheet(isPresented: $showingImport) {
            ScheduleImportView()
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func activeProfile() -> ChildProfile? {
        guard let id = profileStore.selectedProfileID else { return nil }
        return modelContext.model(for: id) as? ChildProfile ?? nil
    }

    @ViewBuilder
    private func profileChip(_ profile: ChildProfile) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(Text(initials(for: profile.name)).font(.headline))
            Text(profile.name.isEmpty ? "Naamloos" : profile.name)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
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
}

struct AddLessonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: ProfileSelectionStore
    @State private var subject: String = ""
    @State private var weekday: Weekday = .monday
    @State private var startTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime: Date = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Vak", text: $subject)
                Picker("Dag", selection: $weekday) {
                    ForEach(Weekday.allCases) { day in
                        Text(day.label).tag(day)
                    }
                }
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("Einde", selection: $endTime, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("Nieuwe les")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", action: save)
                        .disabled(subject.isEmpty || endTime <= startTime)
                }
            }
        }
    }

    private func save() {
        let lesson = Lesson(subject: subject, weekday: weekday, startTime: startTime, endTime: endTime, profile: selectedProfile())
        modelContext.insert(lesson)
        dismiss()
    }

    private func selectedProfile() -> ChildProfile? {
        guard let id = profileStore.selectedProfileID else { return nil }
        return modelContext.model(for: id) as? ChildProfile
    }
}

#Preview {
    NavigationStack { ScheduleView() }
        .modelContainer(for: Lesson.self, inMemory: true)
}
