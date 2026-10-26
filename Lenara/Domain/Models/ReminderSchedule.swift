import Foundation

/// One local wall-clock time, daily (nil weekday) or on a specific weekday (Sunday = 1).
struct ReminderSlot: Codable, Hashable, Identifiable {
    var weekday: Int?
    var hour: Int
    var minute: Int
    var id: String { "\(weekday ?? 0)-\(hour)-\(minute)" }
    var components: DateComponents {
        DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday)
    }
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute),
              weekday == nil || (1...7).contains(weekday!) else { return nil }
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime,
                                 repeatedTimePolicy: .first, direction: .forward)
    }
    var label: String {
        let day = weekday.map { ["", "Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"][$0] } ?? "Todos los días"
        return String(format: "%@ · %02d:%02d", day, hour, minute)
    }
}

struct RecurrenceParseResult {
    var slots: [ReminderSlot] = []
    var title: String
    var question: String?
}

/// Parse schedules before the language model: the model cannot silently invent a time.
struct RecurrenceParser {
    static let days = ["domingo", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado"]
    static let numbers = ["una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
                          "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12]
    static func recognizes(_ text: String) -> Bool {
        text.range(of: #"\b(todos? los|todas las|cada|diari[oa]|diariamente|semanal(?:mente)?|mensual(?:mente)?|quincenal|interdiario|de lunes a viernes|fines de semana|los (lunes|martes|miercoles|jueves|viernes|sabados|domingos))\b"#, options: .regularExpression) != nil
    }

    func parse(_ original: String) -> RecurrenceParseResult? {
        let text = original.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
        guard Self.recognizes(text) else { return nil }
        // Time matches retain source ranges so all schedule syntax can be removed from the title.
        let pattern = #"(?:a las?\s+|(?<=\s)(?=\d{1,2}(?::\d{2}|\s*[ap]\.?\s*m)))(\d{1,2}|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce)(?::(\d{2})|\s+y\s+(media|cuarto))?\s*(de la manana|de la tarde|de la noche|[ap]\.?\s*m\.?)?|(?:al?\s+)?(mediodia|medianoche)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = RecurrenceParseResult(title: original)
        if text.range(of: #"cada\s+(\d+|dos|tres|cuatro)|cada (semana|mes|ano)|hasta |desde |excepto |quincen"#, options: .regularExpression) != nil {
            result.question = "Puedo repetir por días de la semana y varias horas. Indica los días y las horas exactas, sin fecha de inicio o fin."
        }
        let allowedDays = "dia|lunes|martes|miercoles|jueves|viernes|sabado|domingo"
        let unsupported = #"cada\s+(?!(?:"# + allowedDays + #")\b)|\b(meses|anos|mensual|mensualmente|quincenal|interdiario|alternos)\b"#
        let dayRange = #"(?:domingo|lunes|martes|miercoles|jueves|viernes|sabado)\s+a\s+(?:domingo|lunes|martes|miercoles|jueves|viernes|sabado)"#
        if text.range(of: unsupported, options: .regularExpression) != nil ||
            (text.range(of: dayRange, options: .regularExpression) != nil && !text.contains("lunes a viernes")) {
            result.question = "Indica los días de la semana y las horas exactas. Para un rango, enumera los días que quieres incluir."
        }
        guard !matches.isEmpty else {
            result.question = "¿A qué hora debe repetirse? Puedes indicar varias, por ejemplo 9 am y 6 pm."
            return result
        }
        var activeDays: [Int?] = []
        var previousEnd = text.startIndex
        var ranges: [NSRange] = []
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let prefix = String(text[previousEnd..<range.lowerBound])
            let foundDays = Self.days.enumerated().filter { prefix.contains($0.element) }.map { Optional($0.offset + 1) }
            if prefix.contains("lunes a viernes") || prefix.contains("dias laborables") { activeDays = [2, 3, 4, 5, 6] }
            else if prefix.contains("fin de semana") || prefix.contains("fines de semana") { activeDays = [1, 7] }
            else if !foundDays.isEmpty { activeDays = foundDays }
            else if prefix.contains("dias") || prefix.contains("cada dia") || prefix.contains("diario") || prefix.contains("diariamente") { activeDays = [nil] }
            // A schedule written after the hour applies to all times if no earlier day was specified.
            if activeDays.isEmpty {
                let allDays = Self.days.enumerated().filter { text.contains($0.element) }.map { Optional($0.offset + 1) }
                if text.contains("lunes a viernes") { activeDays = [2, 3, 4, 5, 6] }
                else if text.contains("fin de semana") || text.contains("fines de semana") { activeDays = [1, 7] }
                else { activeDays = allDays.isEmpty ? [nil] : allDays }
            }
            func capture(_ i: Int) -> String { Range(match.range(at: i), in: text).map { String(text[$0]) } ?? "" }
            let raw = capture(1)
            var hour = Int(raw) ?? Self.numbers[raw] ?? (capture(5) == "mediodia" ? 12 : 0)
            let minute = Int(capture(2)) ?? (capture(3) == "media" ? 30 : capture(3) == "cuarto" ? 15 : 0)
            let meridiem = capture(4).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            if !meridiem.isEmpty && !(1...12).contains(hour) || hour > 23 || minute > 59 {
                result.question = "Hay una hora inválida. Usa horas entre 00:00 y 23:59 o indica am/pm."
            } else if meridiem.contains("tarde") || meridiem.contains("noche") || meridiem == "pm" {
                if hour < 12 { hour += 12 }
            } else if meridiem.contains("manana") || meridiem == "am" {
                if hour == 12 { hour = 0 }
            } else if capture(5).isEmpty && (1...12).contains(hour) && capture(2).isEmpty {
                result.question = "¿Las \(raw) de la mañana o de la tarde/noche? Puedes usar 05:00 o 17:00."
            }
            result.slots += activeDays.map { ReminderSlot(weekday: $0, hour: hour, minute: minute) }
            previousEnd = range.upperBound
            ranges.append(match.range)
        }
        var title = original as NSString
        for range in ranges.reversed() { title = title.replacingCharacters(in: range, with: " § ") as NSString }
        var cleaned = title as String
        let schedulePattern = #"\b(?:(?:todos? los|todas las|cada|los|las)\s+)?(?:d[ií]as laborables|d[ií]as|d[ií]a|diariamente|diario|diaria|fines de semana|fin de semana|(?:de )?lunes a viernes|lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bados?|domingos?)\b"#
        cleaned = cleaned.replacingOccurrences(of: schedulePattern, with: " § ", options: [.regularExpression, .caseInsensitive])
        cleaned = cleaned.replacingOccurrences(of: #"§(?:\s*[,;]?\s*(?:y luego|y|luego)?\s*§)+"#, with: " § ", options: [.regularExpression, .caseInsensitive])
        cleaned = cleaned.replacingOccurrences(of: "§", with: " ")
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result.title = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        result.slots = Array(Set(result.slots)).sorted { ($0.weekday ?? 0, $0.hour, $0.minute) < ($1.weekday ?? 0, $1.hour, $1.minute) }
        if result.question != nil { result.slots = [] } // Never save only the valid subset.
        return result
    }
}
