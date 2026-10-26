import AppKit
import SwiftUI

enum HighlightTokenKind: Equatable {
    case keyword
    case type
    case string
    case number
    case comment
}

struct HighlightToken: Equatable {
    let range: Range<String.Index>
    let kind: HighlightTokenKind
}

struct CodeTheme {
    struct Colors {
        let keyword: NSColor
        let type: NSColor
        let string: NSColor
        let number: NSColor
        let comment: NSColor

        func nsColor(for kind: HighlightTokenKind) -> NSColor {
            switch kind {
            case .keyword: return keyword
            case .type: return type
            case .string: return string
            case .number: return number
            case .comment: return comment
            }
        }

        func color(for kind: HighlightTokenKind) -> Color {
            Color(nsColor: nsColor(for: kind))
        }
    }

    static func colors(for colorScheme: ColorScheme) -> Colors {
        switch colorScheme {
        case .dark:
            return Colors(
                keyword: NSColor(srgbRed: 0.78, green: 0.55, blue: 0.90, alpha: 1),
                type: NSColor(srgbRed: 0.38, green: 0.82, blue: 0.76, alpha: 1),
                string: NSColor(srgbRed: 0.85, green: 0.62, blue: 0.42, alpha: 1),
                number: NSColor(srgbRed: 0.72, green: 0.84, blue: 0.55, alpha: 1),
                comment: NSColor(srgbRed: 0.48, green: 0.66, blue: 0.44, alpha: 1)
            )
        default:
            return Colors(
                keyword: NSColor(srgbRed: 0.58, green: 0.12, blue: 0.64, alpha: 1),
                type: NSColor(srgbRed: 0.08, green: 0.44, blue: 0.54, alpha: 1),
                string: NSColor(srgbRed: 0.60, green: 0.20, blue: 0.14, alpha: 1),
                number: NSColor(srgbRed: 0.10, green: 0.44, blue: 0.20, alpha: 1),
                comment: NSColor(srgbRed: 0.35, green: 0.50, blue: 0.30, alpha: 1)
            )
        }
    }
}

struct CodeHighlighter {
    static let maxPreviewCharacters = 2_000
    static let maxPreviewLines = 40

    static func preparedText(_ text: String) -> String {
        var prepared = String(text.prefix(maxPreviewCharacters))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")

        if prepared.count > maxPreviewCharacters {
            prepared = String(prepared.prefix(maxPreviewCharacters))
        }

        let lines = prepared.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > maxPreviewLines {
            prepared = lines.prefix(maxPreviewLines).joined(separator: "\n")
        }

        if prepared.count >= maxPreviewCharacters,
           let lastNewline = prepared.lastIndex(of: "\n") {
            prepared = String(prepared[..<lastNewline])
        }
        return prepared
    }

    static func attributedPreview(
        _ text: String,
        language: CodeLanguage,
        colorScheme: ColorScheme
    ) -> AttributedString {
        let prepared = preparedText(text)
        let tokens = tokens(in: prepared, language: language)
        let colors = CodeTheme.colors(for: colorScheme)

        var result = AttributedString()
        var cursor = prepared.startIndex

        for token in tokens {
            guard token.range.lowerBound >= cursor else { continue }
            if cursor < token.range.lowerBound {
                result.append(AttributedString(String(prepared[cursor..<token.range.lowerBound])))
            }
            var piece = AttributedString(String(prepared[token.range]))
            piece.foregroundColor = colors.color(for: token.kind)
            result.append(piece)
            cursor = token.range.upperBound
        }

        if cursor < prepared.endIndex {
            result.append(AttributedString(String(prepared[cursor...])))
        }
        return result
    }

    static func tokens(in text: String, language: CodeLanguage) -> [HighlightToken] {
        let syntax = syntax(for: language)
        var tokens: [HighlightToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            if language == .html {
                if text[index...].hasPrefix("<!--") {
                    let end = text[index...].range(of: "-->").map { $0.upperBound } ?? text.endIndex
                    tokens.append(HighlightToken(range: index..<end, kind: .comment))
                    index = end
                    continue
                }
                if text[index] == "<" {
                    let end = text[index...].firstIndex(of: ">").map {
                        text.index(after: $0)
                    } ?? text.endIndex
                    tokenizeHTMLTag(text, start: index, end: end, into: &tokens)
                    index = end
                    continue
                }
            }

            if let prefix = syntax.lineComments.first(where: {
                text[index...].hasPrefix($0)
            }) {
                let end = text[index...].firstIndex(of: "\n") ?? text.endIndex
                tokens.append(HighlightToken(range: index..<end, kind: .comment))
                index = end
                continue
            }

            if let block = syntax.blockComments.first(where: {
                text[index...].hasPrefix($0.open)
            }) {
                let searchStart = text.index(index, offsetBy: block.open.count)
                if let close = text.range(of: block.close, range: searchStart..<text.endIndex) {
                    tokens.append(
                        HighlightToken(range: index..<close.upperBound, kind: .comment)
                    )
                    index = close.upperBound
                } else {
                    tokens.append(HighlightToken(range: index..<text.endIndex, kind: .comment))
                    index = text.endIndex
                }
                continue
            }

            if let delimiter = syntax.stringDelimiters.first(where: {
                text[index...].hasPrefix($0)
            }) {
                let end = consumeString(in: text, from: index, delimiter: delimiter)
                tokens.append(HighlightToken(range: index..<end, kind: .string))
                index = end
                continue
            }

            let character = text[index]

            if language == .swift, character == "@" {
                var end = text.index(after: index)
                while end < text.endIndex,
                      isIdentifierCharacter(text[end], language: language) {
                    end = text.index(after: end)
                }
                tokens.append(HighlightToken(range: index..<end, kind: .type))
                index = end
                continue
            }

            if language == .css, character == "#" {
                var end = text.index(after: index)
                while end < text.endIndex,
                      "0123456789abcdefABCDEF".contains(text[end]) {
                    end = text.index(after: end)
                }
                if end > text.index(after: index) {
                    tokens.append(HighlightToken(range: index..<end, kind: .number))
                    index = end
                    continue
                }
            }

            if isIdentifierStart(character, language: language) {
                var end = index
                while end < text.endIndex,
                      isIdentifierCharacter(text[end], language: language) {
                    end = text.index(after: end)
                }
                let word = String(text[index..<end])
                let lowercased = word.lowercased()

                if syntax.cssPropertyNames, isFollowedByColon(text, from: end) {
                    tokens.append(HighlightToken(range: index..<end, kind: .type))
                } else if syntax.keywords.contains(lowercased) {
                    tokens.append(HighlightToken(range: index..<end, kind: .keyword))
                } else if syntax.types.contains(lowercased)
                    || (syntax.capitalizedTypes && word.first?.isUppercase == true) {
                    tokens.append(HighlightToken(range: index..<end, kind: .type))
                }

                index = end
                continue
            }

            if character.isNumber
                || (character == "." && nextCharacter(in: text, after: index)?.isNumber == true) {
                var end = index
                while end < text.endIndex {
                    let current = text[end]
                    if current.isNumber || current == "_" {
                        end = text.index(after: end)
                    } else if current == "." {
                        let next = nextCharacter(in: text, after: end)
                        if next?.isNumber == true {
                            end = text.index(after: end)
                        } else {
                            break
                        }
                    } else if syntax.hexNumbers, "abcdefABCDEFxX".contains(current) {
                        end = text.index(after: end)
                    } else {
                        break
                    }
                }
                tokens.append(HighlightToken(range: index..<end, kind: .number))
                index = end
                continue
            }

            index = text.index(after: index)
        }
        return tokens
    }

    private static func consumeString(
        in text: String,
        from start: String.Index,
        delimiter: String
    ) -> String.Index {
        var index = text.index(start, offsetBy: delimiter.count)
        let isMultiline = delimiter.count == 3

        while index < text.endIndex {
            if text[index...].hasPrefix(delimiter) {
                return text.index(index, offsetBy: delimiter.count)
            }
            if !isMultiline, text[index] == "\\" {
                index = text.index(after: index)
                if index < text.endIndex {
                    index = text.index(after: index)
                }
                continue
            }
            if !isMultiline, text[index] == "\n" {
                return index
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    private static func tokenizeHTMLTag(
        _ text: String,
        start: String.Index,
        end: String.Index,
        into tokens: inout [HighlightToken]
    ) {
        if text[start...].hasPrefix("<!") {
            tokens.append(HighlightToken(range: start..<end, kind: .keyword))
            return
        }

        var index = text.index(after: start)
        if index < end, text[index] == "/" {
            index = text.index(after: index)
        }
        while index < end, text[index].isWhitespace {
            index = text.index(after: index)
        }

        let nameStart = index
        while index < end, isHTMLNameCharacter(text[index]) {
            index = text.index(after: index)
        }
        if nameStart < index {
            tokens.append(HighlightToken(range: nameStart..<index, kind: .keyword))
        }

        while index < end {
            while index < end, text[index].isWhitespace {
                index = text.index(after: index)
            }
            if index >= end || text[index] == ">" {
                break
            }
            if text[index] == "/" {
                index = text.index(after: index)
                continue
            }

            let attributeStart = index
            while index < end, isHTMLNameCharacter(text[index]) {
                index = text.index(after: index)
            }
            if attributeStart < index {
                tokens.append(HighlightToken(range: attributeStart..<index, kind: .type))
            } else if text[index] != "=" {
                // No attribute name and not `=`: stray punctuation inside the
                // tag (e.g. `a < b && c > d`). Skip one character so the loop
                // always makes progress — previously this span forever at
                // 100% CPU per offending clipboard item.
                index = text.index(after: index)
                continue
            }

            while index < end, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < end, text[index] == "=" else { continue }
            index = text.index(after: index)
            while index < end, text[index].isWhitespace {
                index = text.index(after: index)
            }

            let valueStart = index
            if index < end, text[index] == "\"" || text[index] == "'" {
                let quote = text[index]
                index = text.index(after: index)
                while index < end, text[index] != quote {
                    index = text.index(after: index)
                }
                if index < end {
                    index = text.index(after: index)
                }
            } else {
                while index < end, !text[index].isWhitespace, text[index] != ">" {
                    index = text.index(after: index)
                }
            }
            if valueStart < index {
                tokens.append(HighlightToken(range: valueStart..<index, kind: .string))
            }
        }
    }

    private static func isIdentifierStart(
        _ character: Character,
        language: CodeLanguage
    ) -> Bool {
        character.isLetter || character == "_"
            || (character == "$" && language == .javascript)
    }

    private static func isIdentifierCharacter(
        _ character: Character,
        language: CodeLanguage
    ) -> Bool {
        character.isLetter || character.isNumber || character == "_"
            || character == "$" || (language == .css && character == "-")
    }

    private static func isHTMLNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-"
            || character == "_" || character == ":" || character == "."
            || character == "@"
    }

    private static func nextCharacter(
        in text: String,
        after index: String.Index
    ) -> Character? {
        let next = text.index(after: index)
        return next < text.endIndex ? text[next] : nil
    }

    private static func isFollowedByColon(_ text: String, from index: String.Index) -> Bool {
        var probe = index
        while probe < text.endIndex, text[probe].isWhitespace {
            probe = text.index(after: probe)
        }
        return probe < text.endIndex && text[probe] == ":"
    }

    private struct Syntax {
        var lineComments: [String] = []
        var blockComments: [(open: String, close: String)] = []
        var stringDelimiters: [String] = []
        var keywords: Set<String> = []
        var types: Set<String> = []
        var capitalizedTypes = false
        var hexNumbers = false
        var cssPropertyNames = false
    }

    private static func syntax(for language: CodeLanguage) -> Syntax {
        switch language {
        case .swift:
            return Syntax(
                lineComments: ["//"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\"\"\"", "\""],
                keywords: [
                    "let", "var", "func", "return", "if", "else", "guard",
                    "for", "in", "while", "switch", "case", "default",
                    "break", "continue", "struct", "class", "enum",
                    "protocol", "extension", "import", "init", "deinit",
                    "self", "super", "true", "false", "nil", "try",
                    "catch", "throw", "throws", "async", "await", "defer",
                    "where", "some", "any", "static", "final", "public",
                    "private", "internal", "fileprivate", "open", "inout",
                    "typealias", "associatedtype", "operator",
                    "precedencegroup"
                ],
                types: [
                    "string", "int", "double", "float", "bool", "array",
                    "dictionary", "optional", "anyobject", "void",
                    "cgfloat", "cgpoint", "cgsize", "cgrect", "uicolor",
                    "nsimage", "nscolor", "date", "data", "url", "error",
                    "result", "set", "range", "index", "character"
                ],
                capitalizedTypes: true
            )
        case .javascript:
            return Syntax(
                lineComments: ["//"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\"", "'", "`"],
                keywords: [
                    "let", "var", "const", "function", "return", "if",
                    "else", "for", "while", "do", "switch", "case",
                    "default", "break", "continue", "class", "extends",
                    "import", "export", "from", "as", "new", "this",
                    "super", "true", "false", "null", "undefined",
                    "typeof", "instanceof", "in", "of", "async", "await",
                    "yield", "try", "catch", "finally", "throw", "delete",
                    "void", "interface", "type", "implements", "enum",
                    "namespace", "declare", "readonly", "public",
                    "private", "protected", "static"
                ],
                types: [
                    "array", "object", "string", "number", "boolean",
                    "promise", "map", "set", "date", "regexp", "error"
                ],
                capitalizedTypes: true,
                hexNumbers: true
            )
        case .python:
            return Syntax(
                lineComments: ["#"],
                stringDelimiters: ["\"\"\"", "'''", "\"", "'"],
                keywords: [
                    "def", "return", "if", "elif", "else", "for",
                    "while", "in", "not", "and", "or", "is", "none",
                    "true", "false", "class", "import", "from", "as",
                    "try", "except", "finally", "raise", "with",
                    "lambda", "yield", "async", "await", "pass",
                    "break", "continue", "global", "nonlocal", "del",
                    "assert", "self"
                ],
                types: [
                    "str", "int", "float", "bool", "list", "dict", "set",
                    "tuple", "bytes", "object", "bytearray", "complex",
                    "frozenset", "memoryview", "range", "slice", "type"
                ]
            )
        case .json:
            return Syntax(
                stringDelimiters: ["\""],
                keywords: ["true", "false", "null"],
                hexNumbers: true
            )
        case .shell:
            return Syntax(
                lineComments: ["#"],
                stringDelimiters: ["\"", "'", "`"],
                keywords: [
                    "if", "then", "else", "elif", "fi", "for", "in",
                    "do", "done", "while", "until", "case", "esac",
                    "function", "return", "export", "local", "readonly",
                    "echo", "cd", "set", "unset", "shift", "source",
                    "alias", "test", "sudo", "exit", "read", "printf"
                ],
                types: []
            )
        case .sql:
            return Syntax(
                lineComments: ["--"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["'", "\"", "`"],
                keywords: [
                    "select", "from", "where", "join", "inner", "left",
                    "right", "outer", "on", "group", "by", "order",
                    "having", "limit", "offset", "insert", "into",
                    "values", "update", "set", "delete", "create",
                    "table", "index", "view", "drop", "alter", "add",
                    "column", "primary", "key", "foreign", "references",
                    "not", "null", "and", "or", "as", "distinct",
                    "count", "sum", "avg", "min", "max", "case", "when",
                    "then", "else", "end", "union", "all", "asc", "desc"
                ],
                types: []
            )
        case .html:
            return Syntax(
                lineComments: [],
                blockComments: [],
                stringDelimiters: [],
                keywords: [],
                types: []
            )
        case .css:
            return Syntax(
                lineComments: [],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\"", "'"],
                keywords: [
                    "media", "import", "keyframes", "supports",
                    "font-face", "charset", "layer", "container",
                    "property", "important", "from", "to"
                ],
                types: [],
                hexNumbers: true,
                cssPropertyNames: true
            )
        case .cLike:
            return Syntax(
                lineComments: ["//"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\"", "'"],
                keywords: [
                    "include", "define", "int", "void", "char", "float",
                    "double", "long", "short", "unsigned", "signed",
                    "struct", "union", "enum", "class", "public",
                    "private", "protected", "static", "final", "const",
                    "let", "var", "func", "fn", "impl", "trait", "mut",
                    "package", "import", "use", "return", "if", "else",
                    "for", "while", "do", "switch", "case", "default",
                    "break", "continue", "new", "delete", "try", "catch",
                    "throw", "throws", "namespace", "using", "template",
                    "typename", "auto", "this", "self", "super", "true",
                    "false", "null", "nil", "none", "go", "defer",
                    "range", "chan", "interface", "map", "string"
                ],
                types: [
                    "int", "void", "char", "float", "double", "bool",
                    "size_t", "uint8_t", "uint16_t", "uint32_t",
                    "uint64_t", "int8_t", "int16_t", "int32_t",
                    "int64_t", "vector", "string", "object", "byte",
                    "list", "dict", "set"
                ],
                capitalizedTypes: true,
                hexNumbers: true
            )
        case .generic:
            return Syntax(
                lineComments: ["//", "#"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\"\"\"", "'''", "\"", "'", "`"],
                keywords: [
                    "let", "var", "const", "function", "func", "def",
                    "class", "struct", "enum", "protocol", "interface",
                    "import", "from", "export", "return", "if", "else",
                    "elif", "guard", "for", "while", "switch", "case",
                    "break", "continue", "try", "catch", "throw",
                    "throws", "async", "await", "true", "false", "null",
                    "nil", "none", "public", "private", "static",
                    "final", "new", "self", "super", "in", "is", "and",
                    "or", "not"
                ],
                types: [
                    "string", "int", "double", "float", "bool", "array",
                    "object", "void", "date", "data", "url", "error",
                    "list", "dict", "set", "map", "tuple", "range"
                ],
                capitalizedTypes: true,
                hexNumbers: true
            )
        }
    }
}
