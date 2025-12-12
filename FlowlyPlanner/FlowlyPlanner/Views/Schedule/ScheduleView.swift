import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Lesson.weekday) private var lessons: [Lesson]
    @State private var showingAdd = false

    var body: some View {
        List {
            ForEach(Weekday.allCases) { day in
                let dayLessons = lessons.filter { $0.weekday == day.rawValue }
                Section(header: Text(day.label)) {
                    if dayLessons.isEmpty {
                        Text("Geen lessen")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dayLessons) { lesson in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(lesson.subject)
                                        .font(.headline)
                                    Text("\(timeString(lesson.startTime)) – \(timeString(lesson.endTime))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
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
            Button(action: { showingAdd = true }) {
                Label("Les", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddLessonView()
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct AddLessonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
        let lesson = Lesson(subject: subject, weekday: weekday, startTime: startTime, endTime: endTime)
        modelContext.insert(lesson)
        dismiss()
    }
}

#Preview {
    NavigationStack { ScheduleView() }
        .modelContainer(for: Lesson.self, inMemory: true)
}
