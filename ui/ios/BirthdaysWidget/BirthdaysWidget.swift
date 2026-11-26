import SwiftUI
import UIKit
import WidgetKit

/// Widget do ecrã principal (Birthdayly+), igual ao do Android
/// (BirthdaysWidget.kt): o próximo aniversário com a fotografia (ou as
/// iniciais) e os dois seguintes. A app guarda as datas e a língua no App
/// Group (lib/services/home_widget_sync.dart); é aqui que se conta quanto
/// falta, por isso "Hoje" e "Amanhã" ficam certos sem abrir a app.
private let appGroup = "group.com.velas.app"

struct Person {
  let name: String
  let initials: String
  let photo: String?
  let days: Int
  let date: Date
  let age: Int?
}

/// Os textos que a app envia já traduzidos, separados por U+001F (ver homeWidgetTexts).
struct Texts {
  let label, empty, add, activate, today, turns, tomorrow, inDays: String
  let months, weekdays: [String]

  static func of(_ raw: String?) -> Texts {
    let f = raw?.components(separatedBy: "\u{1F}") ?? []
    guard f.count == 10 else { return pt }
    return Texts(
      label: f[0], empty: f[1], add: f[2], activate: f[3], today: f[4], turns: f[5], tomorrow: f[6],
      inDays: f[7], months: f[8].components(separatedBy: ","), weekdays: f[9].components(separatedBy: ","))
  }

  /// Antes de a app abrir pela primeira vez.
  static let pt = Texts(
    label: "Aniversários", empty: "Sem aniversários", add: "Toca para acrescentar",
    activate: "Ativa o Birthdayly+ na app", today: "Hoje", turns: "faz {n} anos", tomorrow: "Amanhã",
    inDays: "em {n} dias",
    months: ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"],
    weekdays: ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"])

  func short(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.day, .month], from: date)
    return "\(c.day!) \(months[safe: c.month! - 1] ?? "")"
  }

  private func weekday(_ date: Date) -> String {
    weekdays[safe: Calendar.current.component(.weekday, from: date) - 1] ?? ""
  }

  /// Duas linhas curtas, para caberem ao lado da fotografia.
  func when(_ p: Person) -> String {
    let n = inDays.replacingOccurrences(of: "{n}", with: "\(p.days)")
    switch p.days {
    case 0:
      guard let age = p.age else { return "\(today) 🎂" }
      return "\(today) 🎂\n\(turns.replacingOccurrences(of: "{n}", with: "\(age)"))"
    case 1: return "\(tomorrow)\n\(weekday(p.date))"
    case 2...6: return "\(weekday(p.date).capitalizedFirst)\n\(n)"
    default: return "\(n.capitalizedFirst)\n\(short(p.date))"
    }
  }
}

extension Array {
  subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension String {
  var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct BirthdaysEntry: TimelineEntry {
  let date: Date
  let plus: Bool
  let texts: Texts
  let people: [Person]
}

enum WidgetData {
  /// Uma pessoa por linha: "nome|dia|mês|ano|iniciais|fotografia" (vazios quando não há).
  static func load(now: Date = Date()) -> BirthdaysEntry {
    let store = UserDefaults(suiteName: appGroup)
    let today = Calendar.current.startOfDay(for: now)
    let year = Calendar.current.component(.year, from: today)
    let people = (store?.string(forKey: "people") ?? "").components(separatedBy: "\n").compactMap {
      line -> Person? in
      let parts = line.components(separatedBy: "|")
      guard parts.count >= 3, let day = Int(parts[1]), let month = Int(parts[2]) else { return nil }
      var date = occurrence(year, day, month)
      if date < today { date = occurrence(year + 1, day, month) }
      let days = Calendar.current.dateComponents([.day], from: today, to: date).day ?? 0
      let born = parts.count > 3 ? Int(parts[3]) : nil
      let initials = parts.count > 4 && !parts[4].isEmpty ? parts[4] : String(parts[0].prefix(1)).uppercased()
      return Person(
        name: parts[0], initials: initials, photo: parts.count > 5 && !parts[5].isEmpty ? parts[5] : nil,
        days: days, date: date, age: born.map { Calendar.current.component(.year, from: date) - $0 })
    }.sorted { $0.days < $1.days }
    return BirthdaysEntry(
      date: now, plus: store?.bool(forKey: "plus") ?? false, texts: Texts.of(store?.string(forKey: "texts")),
      people: people)
  }

  /// Como na app: o 29 de fevereiro passa a 28 nos anos não bissextos.
  private static func occurrence(_ year: Int, _ day: Int, _ month: Int) -> Date {
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    let d = month == 2 && day == 29 && !leap ? 28 : day
    return Calendar.current.date(from: DateComponents(year: year, month: month, day: d))!
  }
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> BirthdaysEntry {
    BirthdaysEntry(
      date: Date(), plus: true, texts: .pt,
      people: [Person(name: "Ana", initials: "A", photo: nil, days: 1, date: Date(), age: nil)])
  }

  func getSnapshot(in context: Context, completion: @escaping (BirthdaysEntry) -> Void) {
    completion(WidgetData.load())
  }

  /// Volta a contar os dias à meia-noite.
  func getTimeline(in context: Context, completion: @escaping (Timeline<BirthdaysEntry>) -> Void) {
    let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
    completion(Timeline(entries: [WidgetData.load()], policy: .after(midnight)))
  }
}

struct BirthdaysWidgetView: View {
  let entry: BirthdaysEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    let t = entry.texts
    let first = entry.people.first
    VStack(alignment: .leading, spacing: 8) {
      Text(t.label.uppercased())
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(.white.opacity(0.85))
        .lineLimit(1)
      if !entry.plus {
        highlight(name: "Birthdayly+", detail: t.activate, initials: "+", photo: nil)
      } else if let first {
        highlight(name: first.name, detail: t.when(first), initials: first.initials, photo: first.photo)
        if family != .systemSmall {
          ForEach(Array(entry.people.dropFirst().prefix(2).enumerated()), id: \.offset) { _, p in
            HStack {
              Text(p.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
              Spacer()
              Text(t.short(p.date)).font(.system(size: 11)).foregroundColor(.white.opacity(0.85))
            }
            .foregroundColor(.white)
          }
        }
      } else {
        highlight(name: t.empty, detail: t.add, initials: "🎂", photo: nil)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetBackground(brand)
  }

  private var brand: LinearGradient {
    LinearGradient(
      colors: [Color(red: 0.94, green: 0.33, blue: 0.38), Color(red: 0.90, green: 0.38, blue: 0.66),
               Color(red: 0.67, green: 0.55, blue: 0.89)],
      startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  private func highlight(name: String, detail: String, initials: String, photo: String?) -> some View {
    HStack(spacing: 10) {
      ZStack {
        Circle().fill(Color.white.opacity(0.25))
        Circle().stroke(Color.white.opacity(0.8), lineWidth: 2)
        if let photo, let image = UIImage(contentsOfFile: photo)?.preparingThumbnail(of: CGSize(width: 120, height: 120)) {
          Image(uiImage: image).resizable().scaledToFill().clipShape(Circle())
        } else {
          Text(initials).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
        }
      }
      .frame(width: 46, height: 46)
      VStack(alignment: .leading, spacing: 2) {
        Text(name).font(.system(size: 19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        Text(detail).font(.system(size: 12)).lineLimit(2).foregroundColor(.white.opacity(0.95))
      }
      .foregroundColor(.white)
    }
  }
}

extension View {
  /// iOS 17 pede o fundo pelo containerBackground; antes era um fundo normal.
  @ViewBuilder func widgetBackground<B: View>(_ background: B) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { background }
    } else {
      padding().background(background)
    }
  }
}

@main
struct BirthdaysWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "BirthdaysWidget", provider: Provider()) { entry in
      BirthdaysWidgetView(entry: entry)
    }
    .configurationDisplayName("Birthdayly")
    .description(Texts.of(UserDefaults(suiteName: appGroup)?.string(forKey: "texts")).label)
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
