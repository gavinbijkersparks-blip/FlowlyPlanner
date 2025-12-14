import SwiftUI
import PhotosUI
import SwiftData
import UIKit

struct ScheduleImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Lesson.weekday) private var lessons: [Lesson]

    @State private var selectedDay: Weekday = .monday
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var isProcessing = false
    @State private var status: String?
    @State private var error: String?

    private let importer = ScheduleImportService()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Dag")) {
                    Picker("Weekdag", selection: $selectedDay) {
                        ForEach(Weekday.allCases) { day in
                            Text(day.label).tag(day)
                        }
                    }
                }
                Section(header: Text("Foto van rooster")) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text(image == nil ? "Kies foto" : "Andere foto kiezen")
                            Spacer()
                        }
                    }
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                    }
                }
                Section {
                    Button(action: importSchedule) {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Text("Importeer in rooster")
                        }
                    }
                    .disabled(image == nil || isProcessing)
                }
                if let status {
                    Section {
                        Text(status)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Rooster importeren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadImage(from: newValue) }
            }
        }
    }

    private func importSchedule() {
        guard let image else { return }
        status = nil
        error = nil
        isProcessing = true
        Task {
            do {
                let parsed = try await importer.parse(image: image, weekday: selectedDay)
                if parsed.isEmpty {
                    await MainActor.run {
                        status = "Geen lessen herkend."
                        isProcessing = false
                    }
                    return
                }

                await MainActor.run {
                    let existing = lessons.filter { $0.weekday == selectedDay.rawValue }
                    existing.forEach(modelContext.delete)
                    for lesson in parsed {
                        let newLesson = Lesson(subject: lesson.subject ?? lesson.subjectRaw, weekday: selectedDay, startTime: lesson.start, endTime: lesson.end)
                        modelContext.insert(newLesson)
                    }
                    do {
                        try modelContext.save()
                        status = "Geïmporteerd: \(parsed.count) lessen voor \(selectedDay.label)."
                    } catch {
                        self.error = error.localizedDescription
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    self.image = uiImage
                    self.status = nil
                    self.error = nil
                }
            }
        } catch {
            await MainActor.run {
                self.error = "Kon foto niet laden."
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScheduleImportView()
            .modelContainer(for: [Lesson.self], inMemory: true)
    }
}
