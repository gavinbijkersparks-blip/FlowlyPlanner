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
    @State private var useAIPlanner = false
    @State private var aiEndpoint: String = "https://bijkersparks.nl/api/ai-planner.php"
    @State private var isGenerating = false
    @State private var aiPlanUsed: Bool?

    private let plannerService = PlannerService()
    private let aiPlannerService = AIPlannerService()
    private let exporter = ICSExporter()

    var body: some View {
        VStack {
            settingsRow
            debugInfo
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
                Button {
                    generatePlan()
                } label: {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Text("Genereer")
                    }
                }
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
                let dayEvents = plan.events.filter { weekday(for: $0.start) == day }
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
        isGenerating = true

        if useAIPlanner {
            Task {
                do {
                    let result = try await aiPlannerService.generatePlan(
                        profile: profile,
                        lessons: lessons,
                        homeworkTasks: homework,
                        exams: exams,
                        endpoint: aiEndpoint
                    )
                    await MainActor.run {
                        weekPlan = result.plan
                        warning = result.plan.unplanned.isEmpty ? nil : result.plan.unplanned.joined(separator: "\n")
                        isGenerating = false
                        aiPlanUsed = true
                    }
                } catch {
                    if let aiError = error as? AIPlannerError, aiError == .missingStudyBlocks {
                        await MainActor.run {
                            warning = "AI gaf geen studie/huiswerkblokken. Valt terug op lokale planner."
                        }
                        let result = plannerService.generatePlan(profile: profile, lessons: lessons, homeworkTasks: homework, exams: exams)
                        await MainActor.run {
                            weekPlan = result.plan
                            isGenerating = false
                            aiPlanUsed = false
                        }
                        return
                    }
                    await MainActor.run {
                        warning = "AI planner faalde: \(error.localizedDescription)"
                        isGenerating = false
                    }
                }
            }
        } else {
            let result = plannerService.generatePlan(profile: profile, lessons: lessons, homeworkTasks: homework, exams: exams)
            weekPlan = result.plan
            isGenerating = false
            aiPlanUsed = false
        }
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

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func weekday(for date: Date) -> Weekday {
        let wd = Calendar.current.component(.weekday, from: date) // 1=Sunday ... 7=Saturday
        switch wd {
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .sunday
        }
    }

    private var settingsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Gebruik AI planner", isOn: $useAIPlanner)
            if useAIPlanner {
                TextField("AI endpoint", text: $aiEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                if let usedAI = aiPlanUsed {
                    Text(usedAI ? "Laatst: AI" : "Laatst: lokale planner")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    // Kleine debug-info om te zien wat er beschikbaar is bij het plannen
    private var debugInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lessen: \(lessons.count)  |  Huiswerk: \(homework.count)  |  Toetsen: \(exams.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if homework.isEmpty && exams.isEmpty {
                Text("Geen huiswerk/toetsen aanwezig om in te plannen.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
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
