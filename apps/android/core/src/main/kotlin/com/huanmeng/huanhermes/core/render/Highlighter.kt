package com.huanmeng.huanhermes.core.render

/**
 * Small regex lexer for code blocks and tool output: enough colour to read
 * code on a phone, never enough to stall it. Whole blocks are tokenized (so
 * multi-line strings/comments keep their context); oversized input stays plain.
 */
object Highlighter {
    const val MAX_CHARS = 60_000
    const val MAX_LINES = 1_500

    enum class Kind { Keyword, Type, Str, Comment, Number, Annotation, Function, Added, Removed, Meta }

    data class Token(val start: Int, val end: Int, val kind: Kind)

    private class Rule(val regex: Regex, val kind: Kind)

    fun normalize(language: String?): String? = when (val l = language?.lowercase()?.trim()) {
        null, "" -> null
        "kt", "kts", "kotlin" -> "kotlin"
        "java" -> "java"
        "py", "python", "python3" -> "python"
        "js", "jsx", "javascript", "mjs", "cjs" -> "js"
        "ts", "tsx", "typescript" -> "js"
        "sh", "bash", "zsh", "shell", "console", "shellsession", "fish" -> "shell"
        "json", "jsonc", "json5" -> "json"
        "yml", "yaml" -> "yaml"
        "toml", "ini", "conf", "properties" -> "toml"
        "go", "golang" -> "go"
        "rs", "rust" -> "rust"
        "c", "h", "cpp", "c++", "cc", "hpp", "cxx", "objc" -> "c"
        "cs", "csharp" -> "c"
        "swift" -> "swift"
        "dart" -> "dart"
        "sql", "psql", "mysql", "sqlite" -> "sql"
        "diff", "patch", "udiff" -> "diff"
        "xml", "html", "htm", "svg", "vue", "xhtml" -> "xml"
        "css", "scss", "less" -> "css"
        "rb", "ruby" -> "ruby"
        "php" -> "php"
        "lua" -> "lua"
        "dockerfile", "docker" -> "shell"
        "makefile", "make" -> "shell"
        else -> l
    }

    /** Language from a file name, for tool views (`src/App.kt` → kotlin). */
    fun languageForPath(path: String?): String? {
        val name = path?.substringAfterLast('/')?.lowercase() ?: return null
        if (name == "dockerfile" || name == "makefile") return "shell"
        val ext = name.substringAfterLast('.', "")
        return normalize(ext)?.takeIf { it in RULES.keys }
    }

    fun tokenize(code: String, language: String?): List<Token> {
        if (code.isEmpty() || code.length > MAX_CHARS) return emptyList()
        if (code.count { it == '\n' } > MAX_LINES) return emptyList()
        val lang = normalize(language) ?: return emptyList()
        if (lang == "diff") return diff(code)
        val rules = RULES[lang] ?: return emptyList()
        val out = ArrayList<Token>()
        var i = 0
        // Earliest match wins; ties go to the first rule (comments/strings before keywords).
        val pending = arrayOfNulls<MatchResult>(rules.size)
        for (r in rules.indices) pending[r] = rules[r].regex.find(code, 0)
        while (i < code.length) {
            var best = -1
            var bestStart = Int.MAX_VALUE
            for (r in rules.indices) {
                val cur = pending[r] ?: continue
                val m = if (cur.range.first < i) rules[r].regex.find(code, i).also { pending[r] = it } ?: continue else cur
                if (m.range.first < bestStart) { bestStart = m.range.first; best = r }
            }
            if (best < 0) break
            val m = pending[best]!!
            val end = m.range.last + 1
            if (end <= m.range.first) { i = m.range.first + 1; pending[best] = rules[best].regex.find(code, i); continue }
            out += Token(m.range.first, end, rules[best].kind)
            i = end
            if (out.size > 20_000) return emptyList()
        }
        return out
    }

    private fun diff(code: String): List<Token> {
        val out = ArrayList<Token>()
        var start = 0
        for (line in code.split('\n')) {
            val end = start + line.length
            val kind = when {
                line.startsWith("+++") || line.startsWith("---") -> Kind.Meta
                line.startsWith("@@") -> Kind.Meta
                line.startsWith("+") -> Kind.Added
                line.startsWith("-") -> Kind.Removed
                line.startsWith("diff ") || line.startsWith("index ") -> Kind.Meta
                else -> null
            }
            if (kind != null && end > start) out += Token(start, end, kind)
            start = end + 1
        }
        return out
    }

    private fun kw(vararg words: String) = Regex("""\b(?:${words.joinToString("|")})\b""")

    private val NUMBER = Rule(Regex("""\b(?:0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)[fFlLuU]?\b"""), Kind.Number)
    private val DQ = Rule(Regex(""""(?:[^"\\\n]|\\.)*"?"""), Kind.Str)
    private val SQ = Rule(Regex("""'(?:[^'\\\n]|\\.)*'?"""), Kind.Str)
    private val BT = Rule(Regex("""`(?:[^`\\]|\\.)*`?"""), Kind.Str)
    private val SLASH_COMMENT = Rule(Regex("""//[^\n]*"""), Kind.Comment)
    private val BLOCK_COMMENT = Rule(Regex("""/\*[\s\S]*?(?:\*/|$)"""), Kind.Comment)
    private val HASH_COMMENT = Rule(Regex("""(?<![\w$])#[^\n]*"""), Kind.Comment)
    private val TYPE = Rule(Regex("""\b[A-Z][A-Za-z0-9_]*\b"""), Kind.Type)
    private val CALL = Rule(Regex("""\b[a-z_][A-Za-z0-9_]*(?=\()"""), Kind.Function)
    private val ANNOTATION = Rule(Regex("""@[A-Za-z_][\w.]*"""), Kind.Annotation)

    private val RULES: Map<String, List<Rule>> = mapOf(
        "kotlin" to listOf(
            BLOCK_COMMENT, SLASH_COMMENT, Rule(Regex("\"\"\"[\\s\\S]*?(?:\"\"\"|$)"), Kind.Str), DQ, SQ, ANNOTATION,
            Rule(kw("package", "import", "class", "interface", "object", "fun", "val", "var", "if", "else", "when", "for", "while", "do",
                "return", "break", "continue", "try", "catch", "finally", "throw", "is", "as", "in", "null", "true", "false", "this",
                "super", "data", "sealed", "enum", "companion", "private", "public", "internal", "protected", "override", "open",
                "abstract", "suspend", "inline", "const", "lateinit", "typealias", "by", "init", "constructor"), Kind.Keyword),
            NUMBER, TYPE, CALL,
        ),
        "java" to listOf(
            BLOCK_COMMENT, SLASH_COMMENT, DQ, SQ, ANNOTATION,
            Rule(kw("package", "import", "class", "interface", "enum", "record", "extends", "implements", "new", "if", "else", "for",
                "while", "do", "switch", "case", "default", "return", "break", "continue", "try", "catch", "finally", "throw",
                "throws", "null", "true", "false", "this", "super", "static", "final", "private", "public", "protected",
                "abstract", "void", "int", "long", "boolean", "double", "float", "char", "byte", "short", "var", "instanceof"), Kind.Keyword),
            NUMBER, TYPE, CALL,
        ),
        "python" to listOf(
            HASH_COMMENT, Rule(Regex("(?:'''|\"\"\")[\\s\\S]*?(?:'''|\"\"\"|$)"), Kind.Str), DQ, SQ, ANNOTATION,
            Rule(kw("def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or", "is", "None", "True",
                "False", "import", "from", "as", "with", "try", "except", "finally", "raise", "pass", "break", "continue",
                "lambda", "yield", "async", "await", "global", "nonlocal", "self", "assert", "del", "match", "case"), Kind.Keyword),
            NUMBER, TYPE, CALL,
        ),
        "js" to listOf(
            BLOCK_COMMENT, SLASH_COMMENT, BT, DQ, SQ, ANNOTATION,
            Rule(kw("const", "let", "var", "function", "return", "if", "else", "for", "while", "do", "switch", "case", "default",
                "break", "continue", "new", "class", "extends", "import", "export", "from", "as", "async", "await", "try",
                "catch", "finally", "throw", "typeof", "instanceof", "in", "of", "null", "undefined", "true", "false", "this",
                "interface", "type", "enum", "implements", "readonly", "public", "private", "protected", "static", "void",
                "keyof", "declare", "namespace", "yield"), Kind.Keyword),
            NUMBER, TYPE, CALL,
        ),
        "shell" to listOf(
            HASH_COMMENT, DQ, SQ,
            Rule(kw("if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "in", "function", "return",
                "export", "local", "readonly", "set", "unset", "echo", "cd", "exit", "source", "sudo"), Kind.Keyword),
            Rule(Regex("""\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\$[0-9@#?*!$-]"""), Kind.Type),
            Rule(Regex("""(?<=\s)--?[A-Za-z][\w-]*"""), Kind.Annotation),
            NUMBER,
        ),
        "json" to listOf(
            Rule(Regex(""""(?:[^"\\\n]|\\.)*"(?=\s*:)"""), Kind.Type), DQ,
            Rule(kw("true", "false", "null"), Kind.Keyword), NUMBER,
        ),
        "yaml" to listOf(
            HASH_COMMENT, DQ, SQ, Rule(Regex("""(?m)^\s*-?\s*[\w.\-"']+(?=\s*:)"""), Kind.Type),
            Rule(kw("true", "false", "null", "yes", "no", "on", "off"), Kind.Keyword), NUMBER,
        ),
        "toml" to listOf(
            HASH_COMMENT, Rule(Regex("""(?m)^\s*;[^\n]*"""), Kind.Comment), DQ, SQ,
            Rule(Regex("""(?m)^\s*\[[^\]\n]+\]"""), Kind.Keyword), Rule(Regex("""(?m)^\s*[\w.\-]+(?=\s*=)"""), Kind.Type),
            Rule(kw("true", "false"), Kind.Keyword), NUMBER,
        ),
        "go" to listOf(
            BLOCK_COMMENT, SLASH_COMMENT, BT, DQ, SQ,
            Rule(kw("package", "import", "func", "return", "if", "else", "for", "range", "switch", "case", "default", "break",
                "continue", "go", "defer", "select", "chan", "map", "struct", "interface", "type", "var", "const", "nil",
                "true", "false", "make", "new", "len", "append", "error", "string", "int", "bool", "byte"), Kind.Keyword),
            NUMBER, TYPE, CALL,
        ),
        "rust" to listOf(
            BLOCK_COMMENT, SLASH_COMMENT, DQ, Rule(Regex("""#!?\[[^\]\n]*\]"""), Kind.Annotation),
            Rule(kw("fn", "let", "mut", "pub", "struct", "enum", "impl", "trait", "use", "mod", "crate", "self", "Self", "super",
                "match", "if", "else", "for", "while", "loop", "in", "return", "break", "continue", "as", "ref", "move",
                "async", "await", "where", "type", "const", "static", "unsafe", "dyn", "true", "false", "Some", "None",
                "Ok", "Err"), Kind.Keyword),
            NUMBER, TYPE, Rule(Regex("""\b[a-z_][A-Za-z0-9_]*!"""), Kind.Function), CALL,
        ),
        "c" to listOf(
            BLOCK_COMMENT, SLASH_COMMENT, DQ, SQ, Rule(Regex("""(?m)^\s*#\s*\w+[^\n]*"""), Kind.Annotation),
            Rule(kw("int", "char", "void", "long", "short", "float", "double", "unsigned", "signed", "const", "static",
                "struct", "union", "enum", "typedef", "if", "else", "for", "while", "do", "switch", "case", "default",
                "return", "break", "continue", "sizeof", "class", "public", "private", "protected", "namespace", "using",
                "template", "typename", "new", "delete", "auto", "nullptr", "true", "false", "bool", "virtual", "override",
                "string", "var", "foreach", "null"), Kind.Keyword),
            NUMBER, TYPE, CALL,
        ),
        "swift" to listOf(
            BLOCK_COMMENT, SLASH_COMMENT, DQ, ANNOTATION,
            Rule(kw("func", "let", "var", "class", "struct", "enum", "protocol", "extension", "import", "return", "if", "else",
                "guard", "for", "in", "while", "switch", "case", "default", "break", "continue", "nil", "true", "false",
                "self", "Self", "init", "throws", "throw", "try", "catch", "async", "await", "private", "public", "static"), Kind.Keyword),
            NUMBER, TYPE, CALL,
        ),
        "dart" to listOf(
            BLOCK_COMMENT, SLASH_COMMENT, DQ, SQ, ANNOTATION,
            Rule(kw("import", "class", "extends", "with", "implements", "final", "const", "var", "void", "return", "if", "else",
                "for", "while", "switch", "case", "default", "break", "continue", "new", "null", "true", "false", "this",
                "super", "async", "await", "late", "required", "static", "dynamic", "get", "set", "try", "catch", "throw"), Kind.Keyword),
            NUMBER, TYPE, CALL,
        ),
        "sql" to listOf(
            Rule(Regex("""--[^\n]*"""), Kind.Comment), BLOCK_COMMENT, SQ, DQ,
            Rule(Regex("""(?i)\b(?:select|from|where|insert|into|values|update|set|delete|create|table|index|drop|alter|join|left|right|inner|outer|on|group|by|order|having|limit|offset|and|or|not|null|is|as|distinct|union|all|primary|key|foreign|references|default|exists|in|like|between|case|when|then|else|end)\b"""), Kind.Keyword),
            NUMBER,
        ),
        "xml" to listOf(
            Rule(Regex("""<!--[\s\S]*?(?:-->|$)"""), Kind.Comment), DQ, SQ,
            Rule(Regex("""</?[A-Za-z][\w:.-]*|/?>"""), Kind.Keyword), Rule(Regex("""\b[\w:-]+(?==)"""), Kind.Type),
        ),
        "css" to listOf(
            BLOCK_COMMENT, DQ, SQ, Rule(Regex("""[.#][A-Za-z_][\w-]*"""), Kind.Type),
            Rule(Regex("""\b[a-z-]+(?=\s*:)"""), Kind.Keyword), Rule(Regex("""@[\w-]+"""), Kind.Annotation), NUMBER,
        ),
        "ruby" to listOf(
            HASH_COMMENT, DQ, SQ,
            Rule(kw("def", "end", "class", "module", "if", "elsif", "else", "unless", "while", "until", "for", "in", "do",
                "return", "yield", "begin", "rescue", "ensure", "nil", "true", "false", "self", "require", "attr_accessor"), Kind.Keyword),
            Rule(Regex(""":[A-Za-z_]\w*"""), Kind.Type), NUMBER, TYPE,
        ),
        "php" to listOf(
            BLOCK_COMMENT, SLASH_COMMENT, HASH_COMMENT, DQ, SQ,
            Rule(kw("function", "return", "if", "else", "elseif", "foreach", "for", "while", "class", "public", "private",
                "protected", "static", "new", "echo", "null", "true", "false", "use", "namespace", "array"), Kind.Keyword),
            Rule(Regex("""\$[A-Za-z_]\w*"""), Kind.Type), NUMBER,
        ),
        "lua" to listOf(
            Rule(Regex("""--[^\n]*"""), Kind.Comment), DQ, SQ,
            Rule(kw("local", "function", "end", "if", "then", "else", "elseif", "for", "in", "do", "while", "repeat", "until",
                "return", "nil", "true", "false", "and", "or", "not"), Kind.Keyword),
            NUMBER, CALL,
        ),
    )
}
