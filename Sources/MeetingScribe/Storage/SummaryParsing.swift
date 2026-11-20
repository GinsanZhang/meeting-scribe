import Foundation

/// Parses the LLM summary into key points and todo items. The summary
/// prompt asks for `## 要点`, `## 决定事项`, `## 待办事项` and
/// `## 未决问题` sections; bullet lines under the matching heading
/// become the items. Headings are matched loosely (with or without
/// the `##` markers and any parenthetical), so a differently formatted
/// model reply still parses. Sections the model didn't produce yield
/// empty lists, and callers fall back to the raw summary text.
func parseKeyPoints(from summary: String) -> [String] {
    sectionLines(in: summary, heading: "要点")
}

func parseTodos(from summary: String) -> [TodoItem] {
    sectionLines(in: summary, heading: "待办事项")
        .map { TodoItem(text: $0) }
}

/// Bullet lines under the first heading that matches `heading`
/// (exact, or the heading followed by anything in parentheses).
/// Stops at the next heading. A line counts as a bullet when it
/// starts with "- ", "* ", "• " or a number like "1. ".
private func sectionLines(in summary: String, heading: String) -> [String] {
    let lines = summary.components(separatedBy: .newlines)
    var inSection = false
    var items: [String] = []
    for rawLine in lines {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if isHeading(line) {
            if inSection { break }
            if headingMatches(line, heading: heading) { inSection = true }
            continue
        }
        guard inSection else { continue }
        if let bullet = bulletText(line) {
            items.append(bullet)
        }
    }
    return items.filter { $0 != "无" && !$0.isEmpty }
}

private func isHeading(_ line: String) -> Bool {
    line.hasPrefix("#") || line.hasPrefix("##")
}

private func headingMatches(_ line: String, heading: String) -> Bool {
    var text = line
    while text.hasPrefix("#") { text.removeFirst() }
    text = text.trimmingCharacters(in: .whitespaces)
    if text == heading { return true }
    // "待办事项（每项写清负责人…）" — match the heading before any paren.
    if let paren = text.firstIndex(of: "（") ?? text.firstIndex(of: "(") {
        return String(text[..<paren]) == heading
    }
    return text.hasPrefix(heading)
}

/// Strips a bullet/number prefix; returns nil for non-bullet lines.
private func bulletText(_ line: String) -> String? {
    if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
    // "1. ..." / "1、..." numbered items.
    if let dot = line.firstIndex(of: ".") ?? line.firstIndex(of: "、"),
       line[..<dot].allSatisfy({ $0.isNumber }),
       line.distance(from: line.startIndex, to: dot) <= 2 {
        return String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
    }
    return nil
}
