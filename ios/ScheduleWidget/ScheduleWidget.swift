import SwiftUI
import WidgetKit

private let appGroupId = "group.com.example.raspiflutter"
private let itemSeparator = "\u{241E}"

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let title: String
    let subtitle: String
    let lines: [String]
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(
            date: Date(),
            title: "Расписание",
            subtitle: "На сегодня",
            lines: ["1. Нет данных"]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> ScheduleEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let title = defaults?.string(forKey: "widget_title") ?? "Расписание"
        let subtitle = defaults?.string(forKey: "widget_subtitle") ?? "На сегодня нет данных"
        let payload = defaults?.string(forKey: "widget_day_items") ?? ""
        let lines = payload
            .components(separatedBy: itemSeparator)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ScheduleEntry(
            date: Date(),
            title: title,
            subtitle: subtitle,
            lines: lines
        )
    }
}

struct ScheduleWidgetEntryView: View {
    var entry: ScheduleProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.14, blue: 0.23), Color(red: 0.15, green: 0.24, blue: 0.37)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Divider().overlay(.white.opacity(0.16))
                if entry.lines.isEmpty {
                    Text("Нет занятий")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                } else {
                    ForEach(displayLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    private var displayLines: [String] {
        switch family {
        case .systemSmall:
            return Array(entry.lines.prefix(2))
        case .systemMedium:
            return Array(entry.lines.prefix(4))
        default:
            return Array(entry.lines.prefix(7))
        }
    }
}

struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            ScheduleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Расписание")
        .description("Показывает занятия на текущий день.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
