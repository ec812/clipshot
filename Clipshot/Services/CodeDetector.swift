import Foundation

enum CodeLanguage: String, CaseIterable, Sendable {
    case swift
    case javascript
    case python
    case json
    case shell
    case sql
    case html
    case css
    case cLike
    case generic
}

enum CodeDetector {
    static let maxDetectionCharacters = 16_384

    private static let stopwords: Set<String> = [
        "the", "and", "is", "are", "was", "were", "to", "of", "in", "for",
        "on", "with", "that", "this", "it", "as", "at", "by", "be", "from",
        "or", "an", "we", "you", "i", "they", "he", "she", "but", "not",
        "have", "has", "had", "will", "would", "can", "could", "should",
        "there", "their", "what", "which", "when", "where", "who", "how",
        "why", "all", "any", "some", "more", "most", "other", "into",
        "than", "then", "so", "if", "because", "while", "about", "after",
        "before", "between", "out", "up", "down", "over", "under", "again",
        "further", "once", "here", "both", "each", "few", "its", "our",
        "your", "my", "me", "him", "her", "us", "them", "let", "lets",
        "just", "also", "very", "much", "many", "one", "two", "like"
    ]

    private static let swiftSignals: Set<String> = [
        "func", "guard", "struct", "protocol", "extension", "defer",
        "throws", "async", "await", "some", "init", "switch", "case",
        "import", "let", "var", "enum", "class"
    ]

    private static let javascriptSignals: Set<String> = [
        "function", "const", "let", "var", "class", "async", "await",
        "import", "export", "interface", "console", "require", "document",
        "window", "null", "undefined", "true", "false"
    ]

    private static let pythonSignals: Set<String> = [
        "def", "elif", "lambda", "self", "none", "true", "false",
        "import", "from", "class", "return", "if", "else", "for", "while",
        "try", "except", "with", "as", "print"
    ]

    private static let shellSignals: Set<String> = [
        "sudo", "cd", "echo", "export", "then", "fi", "done", "case",
        "esac", "function", "bash", "zsh", "sh"
    ]

    private static let sqlSignals: Set<String> = [
        "select", "from", "where", "join", "group", "order", "limit",
        "values", "insert", "update", "delete", "create", "table", "set",
        "into", "and", "or"
    ]

    private static let cLikeSignals: Set<String> = [
        "include", "define", "int", "void", "char", "float", "double",
        "struct", "class", "public", "private", "static", "final",
        "return", "namespace", "using", "template", "impl", "mut", "let",
        "func", "nil", "null", "true", "false", "new", "try", "catch",
        "throw", "package", "fmt"
    ]

    static func detect(_ text: String) -> CodeLanguage? {
        let fullSample = String(text.prefix(maxDetectionCharacters))
            .replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = fullSample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return nil }

        if let json = detectJSON(text, sample: trimmed) { return json }
        if let markup = detectMarkup(trimmed) { return markup }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmptyLines.isEmpty else { return nil }

        let words = tokenizeWords(trimmed)
        let wordSet = Set(words)
        let lowercased = trimmed.lowercased()

        let nonSpaceCount = trimmed.filter { !$0.isWhitespace }.count
        var symbolCount = 0
        var braceCount = 0
        var semicolonCount = 0
        var quoteCount = 0
        for character in trimmed {
            switch character {
            case "{", "}", "(", ")", "[", "]", "<", ">", "=", "+", "-",
                 "*", "/", "%", "&", "|", "!", "?", ":", ";", ",", ".",
                 "\"", "'", "#", "@", "\\":
                symbolCount += 1
            default:
                break
            }
            if character == "{" || character == "}" { braceCount += 1 }
            if character == ";" { semicolonCount += 1 }
            if character == "\"" || character == "'" { quoteCount += 1 }
        }

        let indentedLines = nonEmptyLines.filter {
            $0.first == " " || $0.first == "\t"
        }.count
        let proseLines = nonEmptyLines.filter {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line.hasSuffix(".") || line.hasSuffix("?")
                || line.hasSuffix("!") || line.hasSuffix("…")
        }.count
        let stopwordCount = words.filter { stopwords.contains($0) }.count
        let stopwordRatio = Double(stopwordCount) / Double(max(words.count, 1))
        let symbolRatio = Double(symbolCount) / Double(max(nonSpaceCount, 1))
        let averageLineLength = Double(nonSpaceCount) / Double(max(nonEmptyLines.count, 1))

        let hasComment = trimmed.contains("//") || trimmed.contains("/*")
            || trimmed.contains("#") || trimmed.contains("--")
        let hasShebang = trimmed.hasPrefix("#!")
        let hasEmailShape = trimmed.contains("@") && trimmed.contains(".")
            && !trimmed.contains("@MainActor") && !trimmed.contains("@mainactor")

        var scores: [CodeLanguage: Int] = [:]

        func add(_ language: CodeLanguage, _ points: Int, if condition: Bool) {
            guard condition else { return }
            scores[language, default: 0] += points
        }

        add(.swift, 3, if: wordSet.contains("func")
            || wordSet.contains("guard")
            || wordSet.contains("protocol")
            || wordSet.contains("extension")
            || wordSet.contains("defer"))
        add(.swift, 3, if: lowercased.contains("@mainactor")
            || trimmed.contains("->")
            || trimmed.contains("??"))
        add(.swift, 1, if: !swiftSignals.isDisjoint(with: wordSet))
        add(.swift, 1, if: lowercased.contains("import swiftui")
            || lowercased.contains("import foundation"))

        add(.javascript, 3, if: wordSet.contains("function")
            || trimmed.contains("=>")
            || lowercased.contains("console.")
            || lowercased.contains("require(")
            || wordSet.contains("interface")
            || lowercased.contains("export "))
        add(.javascript, 1, if: !javascriptSignals.isDisjoint(with: wordSet))

        add(.python, 3, if: lowercased.contains("def ")
            || lowercased.contains("elif ")
            || lowercased.contains("self.")
            || wordSet.contains("none")
            || lowercased.contains("lambda ")
            || lowercased.contains("print("))
        add(.python, 1, if: !pythonSignals.isDisjoint(with: wordSet))
        add(.python, 1, if: hasIndentedBlocks(nonEmptyLines))

        add(.shell, 5, if: hasShebang)
        add(.shell, 2, if: lowercased.contains("sudo ")
            || lowercased.contains("cd ")
            || lowercased.contains("echo ")
            || lowercased.contains("export ")
            || lowercased.contains(" done")
            || lowercased.contains(" fi"))
        add(.shell, 1, if: !shellSignals.isDisjoint(with: wordSet))

        add(.sql, 4, if: lowercased.contains("select ")
            && lowercased.contains(" from "))
        add(.sql, 3, if: lowercased.contains("insert into")
            || lowercased.contains("create table")
            || (lowercased.contains("update ") && lowercased.contains(" set ")))
        add(.sql, 1, if: !sqlSignals.isDisjoint(with: wordSet))

        add(.cLike, 4, if: lowercased.contains("#include")
            || lowercased.contains("#define")
            || lowercased.contains("public static")
            || lowercased.contains("std::")
            || lowercased.contains("printf(")
            || lowercased.contains("fn ")
            || lowercased.contains("package ")
            || lowercased.contains("fmt."))
        add(.cLike, 1, if: !cLikeSignals.isDisjoint(with: wordSet))

        add(.css, 4, if: lowercased.contains("{")
            && lowercased.contains(":")
            && lowercased.contains(";")
            && (lowercased.contains("color:")
                || lowercased.contains("display:")
                || lowercased.contains("margin:")
                || lowercased.contains("padding:")
                || lowercased.contains("font-")
                || lowercased.contains("background:")
                || lowercased.contains("border:")
                || lowercased.contains("width:")
                || lowercased.contains("height:")))
        add(.css, 2, if: lowercased.contains("@media")
            || lowercased.contains("::"))

        var genericScore = 0
        if nonEmptyLines.count >= 2 { genericScore += 2 }
        if indentedLines >= 2 { genericScore += 1 }
        if braceCount >= 2 { genericScore += 2 }
        if semicolonCount >= 1 { genericScore += 1 }
        if quoteCount >= 2 { genericScore += 1 }
        if hasComment { genericScore += 1 }
        if symbolRatio > 0.08 { genericScore += 1 }
        if averageLineLength < 100 { genericScore += 1 }

        let singleLineLanguage = singleLineCodeLanguage(trimmed)
        if singleLineLanguage != nil { genericScore += 3 }

        let hasCodeStructure = braceCount >= 2 || semicolonCount >= 1
            || indentedLines >= 2 || symbolRatio >= 0.12
        let proseLike = (stopwordRatio > 0.16
            || (proseLines >= 2 && stopwordRatio > 0.10))
            && !hasCodeStructure

        if proseLike { return nil }
        if hasEmailShape && !hasCodeStructure { return nil }

        let ranked = scores.sorted { $0.value > $1.value }
        if let best = ranked.first {
            let runnerUp = ranked.dropFirst().first?.value ?? 0
            if best.value >= 3 && best.value - runnerUp >= 1 {
                return best.key
            }
            if best.value >= 3 && best.value - runnerUp == 0 {
                return genericScore >= 5 ? .generic : nil
            }
        }

        if let singleLineLanguage, genericScore >= 3 { return singleLineLanguage }
        if genericScore >= 5 { return .generic }
        return nil
    }

    private static func detectJSON(_ text: String, sample: String) -> CodeLanguage? {
        guard let first = sample.first, first == "{" || first == "[" else {
            return nil
        }
        let candidate = text.utf8.count <= 65_536 ? text : sample
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] || object is [Any] else {
            return nil
        }
        return .json
    }

    private static func detectMarkup(_ text: String) -> CodeLanguage? {
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("<!doctype")
            || lowercased.contains("<html")
            || (lowercased.contains("<div") && lowercased.contains("</div>")) {
            return .html
        }
        if lowercased.contains("@media") && lowercased.contains("{") {
            return .css
        }
        return nil
    }

    private static func tokenizeWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func hasIndentedBlocks(_ lines: [Substring]) -> Bool {
        lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && (trimmed.hasSuffix(":") || trimmed.hasPrefix("#"))
        }
    }

    private static func singleLineCodeLanguage(_ text: String) -> CodeLanguage? {
        guard !text.contains("\n") else { return nil }
        let lowercased = text.lowercased()

        func starts(_ prefix: String) -> Bool {
            lowercased.hasPrefix(prefix)
        }

        let hasCodeShape = text.contains("=") || text.contains("(")
            || text.contains(":") || text.contains(";") || text.contains("{")
        guard hasCodeShape else { return nil }

        if starts("func ") { return .swift }
        if starts("guard ") { return .swift }
        if starts("def ") { return .python }
        if starts("elif ") { return .python }
        if starts("const ") || starts("function ") { return .javascript }
        if starts("select ") || starts("insert ") || starts("create ") {
            return .sql
        }
        if starts("let ") || starts("var ") || starts("import ")
            || starts("from ") || starts("return ") || starts("class ") {
            return .generic
        }
        return nil
    }
}
