import Foundation

struct Intent {
    enum Action: String, CaseIterable {
        case createMemory = "create_memory"
        case createTask = "create_task"
        case createReminder = "create_reminder"
        case searchMemory = "search_memory"
        case listTasks = "list_tasks"
        case listReminders = "list_reminders"
        case strongAlarm = "strong_alarm"
        case deleteItem = "delete"
        case greeting = "greeting"
        case help = "help"
        case unknown = "unknown"
    }
    let action: Action
    let title: String?
    let content: String?
    let date: Date?
    let isRepeating: Bool?
    let isStrongAlarm: Bool
    let category: MemoryCategory?
    let tags: [String]?
    var recurrenceSlots: [ReminderSlot] = []
    var clarification: String? = nil
}

struct IntentParser {
    private let calendar: Calendar
    init(calendar: Calendar = .current) { self.calendar = calendar }

    func parse(_ text: String, now: Date = .now) -> Intent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = fold(trimmed).lowercased()
        let isStrongAlarm = normalized.contains("alarma fuerte")
        if isStrongAlarm && !hasReminderCommand(normalized) && parseDate(normalized, now: now) == nil && !RecurrenceParser.recognizes(normalized) { return intent(.strongAlarm) }
        if ["hola", "buenos dias", "buenas tardes", "buenas noches", "hey", "que tal"].contains(where: normalized.hasPrefix) {
            return intent(.greeting)
        }
        if ["ayuda", "como funciona", "que puedes hacer", "instrucciones"].contains(where: normalized.contains) { return intent(.help) }
        if normalized.contains("mis tareas") || normalized.contains("tareas pendientes") || normalized.contains("listar tareas") { return intent(.listTasks) }
        if normalized.contains("mis recordatorios") || normalized.contains("listar recordatorios") { return intent(.listReminders) }

        if isMemoryCommand(normalized) {
            let content = memoryContent(trimmed)
            let category: MemoryCategory = normalized.contains("idea") ? .idea : normalized.contains("proyecto") ? .project : .note
            return Intent(action: .createMemory, title: content, content: content, date: nil, isRepeating: nil, isStrongAlarm: false, category: category, tags: hashtags(trimmed))
        }
        if isReminder(normalized) {
            if let recurrence = RecurrenceParser().parse(trimmed) {
                let title = reminderTitle(recurrence.title, normalized: fold(recurrence.title).lowercased())
                return Intent(action: .createReminder, title: title, content: nil,
                              date: recurrence.slots.compactMap { $0.nextDate(after: now, calendar: calendar) }.min(),
                              isRepeating: true, isStrongAlarm: isStrongAlarm, category: nil, tags: nil,
                              recurrenceSlots: recurrence.slots, clarification: recurrence.question)
            }
            let parsedDate = parseDate(normalized, now: now)
            let title = reminderTitle(trimmed, normalized: normalized)
            return Intent(action: .createReminder, title: title, content: nil, date: parsedDate, isRepeating: isRecurring(normalized), isStrongAlarm: isStrongAlarm, category: nil, tags: nil)
        }
        if normalized.hasPrefix("crear tarea") || normalized.hasPrefix("crear una tarea") || normalized.hasPrefix("nueva tarea") || normalized.hasPrefix("tarea:") {
            let title = stripPrefix(trimmed, prefixes: ["crear una tarea:", "crear tarea:", "crear tarea", "nueva tarea:", "nueva tarea", "tarea:"])
            return Intent(action: .createTask, title: title, content: nil, date: parseDate(normalized, now: now), isRepeating: nil, isStrongAlarm: false, category: nil, tags: nil)
        }
        if isSearch(normalized) {
            let query = stripPrefix(trimmed, prefixes: ["¿qué ideas guardé sobre", "que ideas guarde sobre", "¿qué tengo anotado sobre", "que tengo anotado sobre", "buscar sobre", "buscar", "busca", "encuentra"])
            return Intent(action: .searchMemory, title: query, content: nil, date: nil, isRepeating: nil, isStrongAlarm: false, category: nil, tags: nil)
        }
        return intent(.unknown)
    }

    private func parseDate(_ text: String, now: Date) -> Date? {
        guard let phrase = calendarDayPhrase(in: text) else { return parseRelativeDate(text, now: now) }
        let day: Date
        if phrase == "pasado manana" { guard let d = calendar.date(byAdding: .day, value: 2, to: now) else { return nil }; day = d }
        else if phrase == "manana" { guard let d = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }; day = d }
        else if phrase == "hoy" { day = now }
        else if let weekday = weekdayOffset(for: phrase, now: now) {
            guard let d = calendar.date(byAdding: .day, value: weekday, to: now) else { return nil }
            day = d
        } else { return nil }

        let timePattern = #"(?:a las?\s*)?(\d{1,2}|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce)(?::(\d{2}))?\s*(de la manana|de la tarde|de la noche|am|pm)?"#
        let timeText = text.replacingOccurrences(of: "esta noche", with: "de la noche")
            .replacingOccurrences(of: "esta manana", with: "de la manana")
            .replacingOccurrences(of: "esta tarde", with: "de la tarde")
            .replacingOccurrences(of: "por la manana", with: "de la manana")
            .replacingOccurrences(of: "por la noche", with: "de la noche")
            .replacingOccurrences(of: "por la tarde", with: "de la tarde")
            .replacingOccurrences(of: " y media", with: ":30")
            .replacingOccurrences(of: " y cuarto", with: ":15")
        if text.contains("mediodia") || text.contains("medio dia") {
            return date(hour: 12, minute: 0, on: day, after: now)
        }
        if text.contains("medianoche") {
            return date(hour: 0, minute: 0, on: day, after: now)
        }
        guard let regex = try? NSRegularExpression(pattern: timePattern) else { return nil }
        let matches = regex.matches(in: timeText, range: NSRange(timeText.startIndex..., in: timeText))
        guard let match = matches.first(where: { $0.range(at: 3).location != NSNotFound }) ?? matches.first,
              let hourRange = Range(match.range(at: 1), in: timeText),
              let rawHour = hourValue(String(timeText[hourRange])) else { return nil }
        let minute = Range(match.range(at: 2), in: timeText).flatMap { Int(timeText[$0]) } ?? 0
        let meridiem = Range(match.range(at: 3), in: timeText).map { String(timeText[$0]) } ?? ""
        var hour = rawHour
        if meridiem.contains("tarde") || meridiem.contains("noche") || meridiem == "pm" {
            if hour < 12 { hour += 12 }
        } else if meridiem.contains("manana") || meridiem == "am" || text.contains("por la manana") || text.contains("esta manana") {
            if hour == 12 { hour = 0 }
        } else if text.contains("esta noche") || text.contains("por la noche") {
            if hour < 12 { hour += 12 }
        } else if text.contains("por la tarde") || text.contains("esta tarde") {
            if hour < 12 { hour += 12 }
        } else if rawHour > 12 || match.range(at: 2).location != NSNotFound || rawHour == 0 {
            hour = rawHour // Explicit 24-hour clock notation.
        } else { return nil }
        return date(hour: hour, minute: minute, on: day, after: now)
    }

    private func date(hour: Int, minute: Int, on day: Date, after now: Date) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute),
              let result = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), result > now else { return nil }
        return result
    }

    private func parseRelativeDate(_ text: String, now: Date) -> Date? {
        if let regex = try? NSRegularExpression(pattern: #"(?:dentro de|en)\s+(\d+|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce)\s+horas?\s+y\s+media"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text), let amount = durationNumber(String(text[range])) {
            return now.addingTimeInterval((Double(amount) + 0.5) * 60 * 60)
        }
        if text.contains("un cuarto de hora") { return now.addingTimeInterval(15 * 60) }
        if text.contains("media hora") || text.contains("medio hora") { return now.addingTimeInterval(30 * 60) }
        if text.contains("una hora y media") || text.contains("hora y media") { return now.addingTimeInterval(90 * 60) }

        let pattern = #"(?:dentro de|en)\s+(\d+|un par de|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|quince|veinte|treinta|cuarenta|sesenta|noventa|cien)\s+(segundos?|minutos?|horas?|dias?|semanas?|mes(?:es)?|años?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let amount = durationNumber(String(text[amountRange])) else { return nil }
        let unit = String(text[unitRange])
        let multiplier: TimeInterval
        if unit.hasPrefix("segundo") { multiplier = 1 }
        else if unit.hasPrefix("minuto") { multiplier = 60 }
        else if unit.hasPrefix("hora") { multiplier = 60 * 60 }
        else if unit.hasPrefix("dia") { multiplier = 24 * 60 * 60 }
        else if unit.hasPrefix("semana") { multiplier = 7 * 24 * 60 * 60 }
        else if unit.hasPrefix("mes") { return calendar.date(byAdding: .month, value: amount, to: now) }
        else if unit.hasPrefix("año") { return calendar.date(byAdding: .year, value: amount, to: now) }
        else { multiplier = 0 }
        return now.addingTimeInterval(TimeInterval(amount) * multiplier)
    }

    private func isReminder(_ text: String) -> Bool {
        ["recuerdame", "acuerdame", "acuerdate", "hazme acordar", "hazme recordar", "recuerde me", "recordatorio", "avisame", "avisa me", "no te olvides", "no me dejes olvidar", "alerta", "alarma fuerte"].contains(where: text.contains)
    }
    private func hasReminderCommand(_ text: String) -> Bool {
        ["recuerdame", "acuerdame", "acuerdate", "hazme acordar", "hazme recordar", "recuerde me", "recordatorio", "avisame", "avisa me", "no te olvides", "no me dejes olvidar"].contains(where: text.contains)
    }
    private func isMemoryCommand(_ text: String) -> Bool {
        ["memoria ", "memoria:", "guarda", "guardar", "registra", "anota", "crear nota"].contains(where: text.hasPrefix)
    }
    private func isSearch(_ text: String) -> Bool { ["buscar", "que tengo", "encuentra", "busca", "que ideas guarde"].contains(where: text.contains) }
    private func isRecurring(_ text: String) -> Bool { text.contains("cada dia") || text.contains("cada semana") || text.contains("diario") || text.contains("semanal") }

    private func reminderTitle(_ original: String, normalized: String) -> String? {
        let prefixes = [
            "pon una alarma fuerte para", "ponme una alarma fuerte para", "crea una alarma fuerte para", "alarma fuerte para",
            "no me dejes olvidar", "no te olvides de", "recuérdame que", "recuerdame que", "recuerde me",
            "hazme acordar de", "hazme acordar", "avísame de", "avisame de", "avisa me",
            "recuérdame", "recuerdame", "acuérdame", "acuerdame", "acuérdate de", "acuerdate de", "hazme acordar de", "hazme recordar", "no te olvides de", "avísame", "avisame",
            "crea un recordatorio para", "crea recordatorio para", "crear un recordatorio para",
            "crear recordatorio para", "ponme un recordatorio para", "pon un recordatorio para",
            "recordatorio:", "alerta:"
        ]
        let leadingDuration = #"^\s*(?:dentro de|en)\s+(?:(?:un cuarto de hora|media hora|medio hora|una hora y media)|(?:\d+|un par de|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|quince|veinte|treinta|cuarenta|sesenta|noventa|cien)\s+horas?\s+y\s+media|(?:\d+|un par de|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|quince|veinte|treinta|cuarenta|sesenta|noventa|cien)\s+(?:segundos?|minutos?|horas?|d[ií]as?|semanas?|mes(?:es)?|años?))\s*[,;:]?\s*"#
        let withoutLeadingDuration = original.replacingOccurrences(of: leadingDuration, with: "", options: [.regularExpression, .caseInsensitive])
        var result = stripPrefix(withoutLeadingDuration, prefixes: prefixes)
        result = result.replacingOccurrences(of: #"\balarma\s+fuerte\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: leadingDuration, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\b(?:dentro de|en)\s+(?:un minuto|una hora|un día|un dia)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let dayPhrase = calendarDayPhrase(in: normalized) {
            if ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"].contains(dayPhrase) {
                result = result.replacingOccurrences(of: #"\s+(?:el\s+)?(?:pr[oó]ximo\s+)?(?:lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bado|domingo)"#, with: "", options: [.regularExpression, .caseInsensitive])
            } else if let range = result.range(of: dayPhrase, options: [.caseInsensitive, .diacriticInsensitive]) {
                result.removeSubrange(range)
            }
        }
        result = result.replacingOccurrences(of: #"\s+(?:dentro de|en)\s+(?:(?:un cuarto de hora|media hora|medio hora|una hora y media)|(?:\d+|un par de|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|quince|veinte|treinta|cuarenta|sesenta|noventa|cien)\s+horas?\s+y\s+media|(?:\d+|un par de|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|quince|veinte|treinta|cuarenta|sesenta|noventa|cien)\s+(?:segundos?|minutos?|horas?|d[ií]as?|semanas?|mes(?:es)?|años?))"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\s+una hora y media"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\s+a las?\s+(?:\d{1,2}|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce)(?::\d{2}|\s+y\s+(?:media|cuarto))?(?:\s*(?:de la (?:mañana|manana|tarde|noche)|am|pm))?"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\s+(?:el\s+)?(?:pr[oó]ximo\s+)?(?:lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bado|domingo)"#, with: "", options: [.regularExpression, .caseInsensitive])
        for phrase in [" esta mañana", " esta manana", " esta tarde", " esta noche", " al mediodía", " al mediodia", " a medianoche", " de la mañana", " de la manana", " de la tarde", " de la noche", " por la mañana", " por la manana", " por la tarde", " por la noche", " am", " pm"] { result = result.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive) }
        _ = normalized
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return cleaned.isEmpty ? nil : cleaned
    }

    private func calendarDayPhrase(in text: String) -> String? {
        if text.contains("pasado manana") { return "pasado manana" }
        if text.contains("hoy") { return "hoy" }
        if text.contains("esta manana") || text.contains("esta tarde") || text.contains("esta noche") { return "hoy" }
        for weekday in ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"] where text.contains(weekday) {
            return weekday
        }
        var searchStart = text.startIndex
        while let range = text.range(of: "manana", range: searchStart..<text.endIndex) {
            let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !prefix.hasSuffix("de la") { return "manana" }
            searchStart = range.upperBound
        }
        return nil
    }

    private func weekdayOffset(for weekday: String, now: Date) -> Int? {
        let weekdays = ["domingo", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado"]
        guard let target = weekdays.firstIndex(of: weekday),
              let current = calendar.dateComponents([.weekday], from: now).weekday else { return nil }
        let offset = (target + 1 - current + 7) % 7
        return offset == 0 ? 7 : offset
    }

    private func durationNumber(_ value: String) -> Int? {
        if let number = Int(value) { return number }
        return ["un par de": 2, "un": 1, "una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4,
                "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
                "diez": 10, "once": 11, "doce": 12, "quince": 15,
                "veinte": 20, "treinta": 30, "cuarenta": 40, "sesenta": 60,
                "noventa": 90, "cien": 100][value]
    }

    private func hourValue(_ value: String) -> Int? {
        if let number = Int(value) { return number }
        return ["una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6,
                "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12][value]
    }

    private func memoryContent(_ text: String) -> String? {
        var value = stripPrefix(text, prefixes: ["memoria:", "memoria", "guarda esta idea:", "guarda la idea:", "guarda esta nota:", "guarda:", "guardar:", "guardar", "guarda", "anota:", "anota", "registra:", "registra"])
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    private func hashtags(_ text: String) -> [String]? {
        let tags = text.split(whereSeparator: { $0.isWhitespace }).filter { $0.hasPrefix("#") }.map { String($0.dropFirst()).lowercased() }
        return tags.isEmpty ? nil : tags
    }
    private func stripPrefix(_ text: String, prefixes: [String]) -> String {
        for prefix in prefixes where fold(text).lowercased().hasPrefix(fold(prefix).lowercased()) {
            let offset = prefix.count
            return String(text.dropFirst(min(offset, text.count))).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func fold(_ value: String) -> String { value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_PE")) }
    private func intent(_ action: Intent.Action) -> Intent { Intent(action: action, title: nil, content: nil, date: nil, isRepeating: nil, isStrongAlarm: false, category: nil, tags: nil) }
}
