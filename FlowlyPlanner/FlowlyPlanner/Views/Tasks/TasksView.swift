import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var homework: [HomeworkTask]
    @Query private var exams: [ExamPreparation]
    @State private var selection: TaskTab = .homework
    @State private var showingAdd = false

    var body: some View {
        VStack {
            Picker("Categorie", selection: $selection) {
                Text("Huiswerk").tag(TaskTab.homework)
                Text("Toetsen").tag(TaskTab.exam)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            List {
                switch selection {
                case .homework:
                    ForEach(homework) { task in
                        VStack(alignment: .leading) {
                            Text(task.title)
                                .font(.headline)
                            Text("\(task.subject) • Deadline: \(format(date: task.deadline)) • \(task.estimatedMinutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { homework[$0] }.forEach(modelContext.delete)
                    }
                case .exam:
                    ForEach(exams) { exam in
                        VStack(alignment: .leading) {
                            Text("Toets – \(exam.subject)")
                                .font(.headline)
                            Text("Datum: \(format(date: exam.examDate)) • Blokken: \(exam.blocksNeeded)x\(exam.blockDurationMinutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { exams[$0] }.forEach(modelContext.delete)
                    }
                }
            }
        }
        .navigationTitle("Taken")
        .toolbar {
            Button { showingAdd = true } label: {
                Label("Taak", systemImage: "plus")
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
}

enum TaskTab { case homework, exam }

struct AddHomeworkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
        let task = HomeworkTask(title: title, subject: subject, deadline: deadline, estimatedMinutes: estimatedMinutes)
        modelContext.insert(task)
        dismiss()
    }
}

struct AddExamView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
        let exam = ExamPreparation(subject: subject, examDate: examDate, blocksNeeded: blocksNeeded, blockDurationMinutes: blockDuration)
        modelContext.insert(exam)
        dismiss()
    }
}

#Preview {
    NavigationStack { TasksView() }
        .modelContainer(for: [HomeworkTask.self, ExamPreparation.self], inMemory: true)
}
