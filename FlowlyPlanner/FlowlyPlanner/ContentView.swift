import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { ProfileView() }
                .tabItem { Label("Profiel", systemImage: "person.crop.circle") }
            NavigationStack { ScheduleView() }
                .tabItem { Label("Rooster", systemImage: "calendar") }
            NavigationStack { TasksView() }
                .tabItem { Label("Taken", systemImage: "checklist") }
            NavigationStack { PlannerView() }
                .tabItem { Label("Planner", systemImage: "clock") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ChildProfile.self, Lesson.self, HomeworkTask.self, ExamPreparation.self], inMemory: true)
}
