import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: ProfileSelectionStore
    @Query private var profiles: [ChildProfile]
    @Query private var homework: [HomeworkTask]
    @Query private var exams: [ExamPreparation]
    @State private var selection: TaskTab = .homework
    @State private var showingAdd = false

    private var filteredHomework: [HomeworkTask] {
        guard let id = profileStore.selectedProfileID else { return homework }
        return homework.filter { $0.profile?.persistentModelID == id || $0.profile == nil }
    }
    private var filteredExams: [ExamPreparation] {
        guard let id = profileStore.selectedProfileID else { return exams }
        return exams.filter { $0.profile?.persistentModelID == id || $0.profile == nil }
    }

    var body: some View {
        VStack {
            if let profile = activeProfile() {
                profileChip(profile)
            } else {
                Text("Selecteer een profiel via het avatar-overzicht.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Picker("Categorie", selection: $selection) {
                Text("Huiswerk").tag(TaskTab.homework)
                Text("Toetsen").tag(TaskTab.exam)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            List {
                switch selection {
                case .homework:
                    ForEach(filteredHomework) { task in
                        VStack(alignment: .leading) {
                            Text(task.title)
                                .font(.headline)
                            Text("\(task.subject) • Deadline: \(format(date: task.deadline)) • \(task.estimatedMinutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { filteredHomework[$0] }.forEach(modelContext.delete)
                    }
                case .exam:
                    ForEach(filteredExams) { exam in
                        VStack(alignment: .leading) {
                            Text("Toets – \(exam.subject)")
                                .font(.headline)
                            Text("Datum: \(format(date: exam.examDate)) • Blokken: \(exam.blocksNeeded)x\(exam.blockDurationMinutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { filteredExams[$0] }.forEach(modelContext.delete)
                    }
                }
            }
        }
        .navigationTitle("Taken")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus.circle")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: ProfileView()) {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            if selection == .homework {
                AddHomeworkView()
            } else {
                AddExamView()
            }
        }
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func activeProfile() -> ChildProfile? {
        guard let id = profileStore.selectedProfileID else { return nil }
        return modelContext.model(for: id) as? ChildProfile ?? profiles.first(where: { $0.persistentModelID == id })
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

enum TaskTab { case homework, exam }

struct AddHomeworkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: ProfileSelectionStore
    @State private var title: String = ""
    @State private var subject: String = ""
    @State private var deadline: Date = Date()
    @State private var estimatedMinutes: Int = 30

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titel", text: $title)
                TextField("Vak", text: $subject)
                DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                Stepper("Geschatte duur: \(estimatedMinutes) min", value: $estimatedMinutes, in: 15...240, step: 15)
            }
            .navigationTitle("Huiswerk")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", action: save)
                        .disabled(title.isEmpty || subject.isEmpty)
                }
            }
        }
    }

    private func save() {
        let task = HomeworkTask(title: title, subject: subject, deadline: deadline, estimatedMinutes: estimatedMinutes, profile: selectedProfile())
        modelContext.insert(task)
        dismiss()
    }

    private func selectedProfile() -> ChildProfile? {
        guard let id = profileStore.selectedProfileID else { return nil }
        return modelContext.model(for: id) as? ChildProfile
    }
}

struct AddExamView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: ProfileSelectionStore
    @State private var subject: String = ""
    @State private var examDate: Date = Date()
    @State private var blocksNeeded: Int = 3
    @State private var blockDuration: Int = 30

    var body: some View {
        NavigationStack {
            Form {
                TextField("Vak", text: $subject)
                DatePicker("Toetsdatum", selection: $examDate, displayedComponents: .date)
                Stepper("Leerblokken: \(blocksNeeded)", value: $blocksNeeded, in: 1...10)
                Stepper("Blokduur: \(blockDuration) min", value: $blockDuration, in: 15...120, step: 15)
            }
            .navigationTitle("Nieuwe toets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", action: save)
                        .disabled(subject.isEmpty)
                }
            }
        }
    }

    private func save() {
        let exam = ExamPreparation(subject: subject, examDate: examDate, blocksNeeded: blocksNeeded, blockDurationMinutes: blockDuration, profile: selectedProfile())
        modelContext.insert(exam)
        dismiss()
    }

    private func selectedProfile() -> ChildProfile? {
        guard let id = profileStore.selectedProfileID else { return nil }
        return modelContext.model(for: id) as? ChildProfile
    }
}

#Preview {
    NavigationStack { TasksView() }
        .modelContainer(for: [HomeworkTask.self, ExamPreparation.self], inMemory: true)
}
