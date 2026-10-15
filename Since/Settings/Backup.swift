import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Everything in the database as one JSON file. There's no iCloud, so this is the way to move or keep data.
struct Backup: Codable {
    struct CounterData: Codable {
        var id: UUID
        var title: String
        var symbol: String
        var color: String
        var kind: String
        var tinted: Bool
        /// Missing in backups made before card sizes existed.
        var size: String?
        var startDate: Date
        var note: String?
        var sortOrder: Int
        var createdAt: Date
        var notifyMilestones: Bool
        var resets: [ResetData]
    }

    struct ResetData: Codable {
        var id: UUID
        var date: Date
        var note: String?
    }

    struct CountdownData: Codable {
        var id: UUID
        var title: String
        var symbol: String
        var color: String
        var tinted: Bool
        var size: String
        var date: Date
        var repeatRule: RepeatRule?
        /// Only in backups made before custom repeats.
        var repeatsYearly: Bool?
        var note: String?
        var sortOrder: Int
        var createdAt: Date
        var notifyBefore: Bool
        var isArchived: Bool
        /// Missing in backups made before imports.
        var countsYears: Bool?
        /// Missing in backups made before countdown styles.
        var style: String?
    }

    var version = 1
    var exportedAt = Date.now
    var counters: [CounterData]
    /// Missing in backups made before countdowns existed.
    var countdowns: [CountdownData]?

    init(counters: [Counter], countdowns: [Countdown] = []) {
        self.countdowns = countdowns.map { countdown in
            CountdownData(id: countdown.id, title: countdown.title, symbol: countdown.symbol, color: countdown.colorName,
                          tinted: countdown.tinted, size: countdown.sizeRaw, date: countdown.date,
                          repeatRule: countdown.rule, note: countdown.note, sortOrder: countdown.sortOrder,
                          createdAt: countdown.createdAt, notifyBefore: countdown.notifyBefore,
                          isArchived: countdown.isArchived, countsYears: countdown.countsYears,
                          style: countdown.styleRaw)
        }
        self.counters = counters.map { counter in
            CounterData(id: counter.id, title: counter.title, symbol: counter.symbol, color: counter.colorName,
                        kind: counter.kindRaw, tinted: counter.tinted, size: counter.sizeRaw, startDate: counter.startDate,
                        note: counter.note, sortOrder: counter.sortOrder, createdAt: counter.createdAt,
                        notifyMilestones: counter.notifyMilestones,
                        resets: counter.resets.sorted { $0.date < $1.date }.map {
                            ResetData(id: $0.id, date: $0.date, note: $0.note)
                        })
        }
    }

    static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Backup.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Deletes every counter, then inserts the ones from the backup. Countdowns are replaced the same way,
    /// unless the backup is older than countdowns and has none: then the ones here are kept.
    func restore(into context: ModelContext) throws {
        // One by one, so the cascade removes resets too and unsaved objects go as well.
        for counter in try context.fetch(FetchDescriptor<Counter>()) {
            context.delete(counter)
        }
        for data in counters {
            let counter = Counter(title: data.title, symbol: data.symbol,
                                  color: CounterColor(rawValue: data.color) ?? .blue,
                                  kind: CounterKind(rawValue: data.kind) ?? .quit,
                                  startDate: data.startDate, note: data.note, sortOrder: data.sortOrder)
            counter.id = data.id
            counter.tinted = data.tinted
            counter.sizeRaw = data.size ?? CardSize.m.rawValue
            counter.createdAt = data.createdAt
            counter.notifyMilestones = data.notifyMilestones
            context.insert(counter)
            for resetData in data.resets {
                let reset = Reset(date: resetData.date, note: resetData.note)
                reset.id = resetData.id
                counter.resets.append(reset)
            }
        }

        guard let countdowns else { return }
        for countdown in try context.fetch(FetchDescriptor<Countdown>()) {
            context.delete(countdown)
        }
        for data in countdowns {
            let countdown = Countdown(title: data.title, symbol: data.symbol,
                                      color: CounterColor(rawValue: data.color) ?? .blue, date: data.date,
                                      rule: data.repeatRule ?? (data.repeatsYearly == true ? RepeatRule(frequency: .yearly) : .never),
                                      note: data.note, sortOrder: data.sortOrder)
            countdown.id = data.id
            countdown.tinted = data.tinted
            countdown.sizeRaw = data.size
            countdown.createdAt = data.createdAt
            countdown.notifyBefore = data.notifyBefore
            countdown.isArchived = data.isArchived
            countdown.countsYears = data.countsYears ?? true
            countdown.styleRaw = data.style ?? CountdownStyle.calendar.rawValue
            context.insert(countdown)
        }
    }
}

/// Wraps backup data for the system's file exporter.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
