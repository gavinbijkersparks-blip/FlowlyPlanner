import SwiftUI
import SwiftData
import UIKit

struct PlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Lesson.weekday) private var lessons: [Lesson]
    @Query private var homework: [HomeworkTask]
    @Query private var exams: [ExamPreparation]

    @State private var weekPlan: WeekPlan?
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var warning: String?

    private let plannerService = PlannerService()
    private let exporter = ICSExporter()

    var body: some View {
        VStack {
            if let plan = weekPlan {
                planList(plan)
            } else {
                ContentUnavailableView(
                    "Geen planning",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Voer profiel, rooster en taken in en genereer een weekplanning.")
                )
            }
            if let warning = warning {
                Text(warning)
                    .foregroundStyle(.orange)
                    .padding()
            }
            Spacer()
        }
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Genereer", action: generatePlan)
                if weekPlan != nil {
                    Button("Export .ics", action: exportPlan)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    @ViewBuilder
    private func planList(_ plan: WeekPlan) -> some View {
        List {
            ForEach(Weekday.allCases) { day in
                let dayEvents = plan.events.filter { Calendar.current.isDate($0.start, inSameDayAs: date(for: day, in: plan.weekStart)) }
                Section(header: Text(day.label)) {
                    if dayEvents.isEmpty {
                        Text("Geen blokken")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dayEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headline)
                                Text("\(timeString(event.start)) – \(timeString(event.end))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !plan.unplanned.isEmpty {
                Section(header: Text("Niet ingepland")) {
                    ForEach(plan.unplanned, id: \.self) { item in
                        Text(item)
                    }
                }
            }
        }
    }

    private func generatePlan() {
        guard let profile = profiles.first else {
            warning = "Maak eerst een kindprofiel"
            return
        }
        warning = nil
        let result = plannerService.generatePlan(profile: profile, lessons: lessons, homeworkTasks: homework, exams: exams)
        weekPlan = result.plan
    }

    private func exportPlan() {
        guard let plan = weekPlan else { return }
        let icsString = exporter.export(events: plan.events)
        let url = saveICS(content: icsString)
        shareURL = url
        showShare = url != nil
    }

    private func saveICS(content: String) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("weekplanner.ics")
        do {
            try content.data(using: .utf8)?.write(to: tempURL)
            return tempURL
        } catch {
            warning = "Kon .ics niet opslaan"
            return nil
        }
    }

    private func date(for weekday: Weekday, in weekStart: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: weekday.rawValue, to: weekStart) ?? weekStart
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack { PlannerView() }
        .modelContainer(for: [ChildProfile.self, Lesson.self, HomeworkTask.self, ExamPreparation.self], inMemory: true)
}
