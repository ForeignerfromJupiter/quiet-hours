import Foundation

/// One word of the sentence. `isHourWord` is set in italic.
struct ProseToken: Equatable {
    var text: String
    var isHourWord = false
}

/// The time as an English sentence. Pure: no UI, unit-tested against the PRD's Prose table.
/// Port of the prototype's `proseTokens(h, m)` plus the "to noon" decision (PRD, Nov 8 2026).
/// Other languages can be added as sibling functions with the same shape.
enum ProseSentence {
    private static let hourWords = ["twelve", "one", "two", "three", "four", "five",
                                    "six", "seven", "eight", "nine", "ten", "eleven"]
    private static let minuteWords: [Int: String] = [5: "five", 10: "ten", 15: "a quarter", 20: "twenty",
                                                     25: "twenty-five", 35: "twenty-five", 40: "twenty",
                                                     45: "a quarter", 50: "ten", 55: "five"]

    /// - Parameters: hour 0–23, minute 0–59.
    static func tokens(hour h: Int, minute m: Int) -> [ProseToken] {
        // Round to the nearest five: +1/+2 → "just after", +3/+4 → "nearly" the next mark.
        let rem = m % 5
        var mark = m - rem
        var lead: [String] = []
        if rem == 1 || rem == 2 { lead = ["just", "after"] }
        else if rem >= 3 { mark += 5; lead = ["nearly"] }

        // The hour that gets named: the next one from "twenty-five to" onward.
        var named = h
        if mark == 60 { mark = 0; named = h + 1 } else if mark > 30 { named = h + 1 }
        named %= 24

        var out = [ProseToken(text: "It's")] + lead.map { ProseToken(text: $0) }
        let special: String?
        if named == 0 { special = "midnight" }
        else if named == 12 && (mark == 0 || mark > 30) { special = "noon" }   // "to noon" (decision)
        else { special = nil }
        let hourWord = ProseToken(text: special ?? hourWords[named % 12], isHourWord: true)

        if mark == 0 {
            out.append(hourWord)
            if special == nil { out.append(ProseToken(text: "o'clock")) }
        } else if mark == 30 {
            out += [ProseToken(text: "half"), ProseToken(text: "past"), hourWord]
        } else {
            out += minuteWords[mark, default: ""].split(separator: " ").map { ProseToken(text: String($0)) }
            out += [ProseToken(text: mark < 30 ? "past" : "to"), hourWord]
        }

        if special == nil {
            let partOfDay: [String]
            switch named {
            case 0..<5: partOfDay = ["at", "night"]
            case 5..<12: partOfDay = ["in", "the", "morning"]
            case 12..<17: partOfDay = ["in", "the", "afternoon"]
            case 17..<21: partOfDay = ["in", "the", "evening"]
            default: partOfDay = ["at", "night"]
            }
            out += partOfDay.map { ProseToken(text: $0) }
        }
        out[out.count - 1].text += "."
        return out
    }

    /// The sentence in the PRD table's notation: hour word wrapped in *asterisks*, period outside.
    static func markdown(_ tokens: [ProseToken]) -> String {
        tokens.map { t in
            guard t.isHourWord else { return t.text }
            if t.text.hasSuffix(".") { return "*\(t.text.dropLast())*." }
            return "*\(t.text)*"
        }.joined(separator: " ")
    }

    /// On-screen form of a word: typographic apostrophes (decision: curly on screen only).
    static func display(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "\u{2019}")
    }
}

/// Word-level diff used by the rewrite: the shared start and end stay untouched.
enum ProseDiff {
    /// Number of equal tokens at the start (`prefix`) and, after that, at the end (`suffix`).
    static func sharedEnds(_ old: [ProseToken], _ new: [ProseToken]) -> (prefix: Int, suffix: Int) {
        var a = 0
        while a < old.count, a < new.count, old[a] == new[a] { a += 1 }
        var b = 0
        while b < old.count - a, b < new.count - a, old[old.count - 1 - b] == new[new.count - 1 - b] { b += 1 }
        return (a, b)
    }
}
