import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var profileStore = ProfileSelectionStore()
    var body: some View {
        TabView {
            NavigationStack { ScheduleView() }
                .tabItem { Label("Rooster", systemImage: "calendar") }
            NavigationStack { TasksView() }
                .tabItem { Label("Taken", systemImage: "checklist") }
            NavigationStack { PlannerView() }
                .tabItem { Label("Planner", systemImage: "clock") }
        }
        .environmentObject(profileStore)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ChildProfile.self, Lesson.self, HomeworkTask.self, ExamPreparation.self], inMemory: true)
}
