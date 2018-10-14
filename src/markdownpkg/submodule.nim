# This is just an example to get you started. Users of your hybrid library will
# import this file by writing ``import markdownpkg/submodule``. Feel free to rename or
# remove this file altogether. You may create additional modules alongside
# this file as required.

import re, strutils, strformat, tables, sequtils, math

type
  MarkdownError* = object of Exception

  # Type for header element
  Header* = object
    doc: string
    level: int

  # Type for fencing block code
  Fence* = object
    code: string
    lang: string

  # Signify the token type
  MarkdownTokenType* {.pure.} = enum
    Header,
    IndentedBlockCode,
    FencingBlockCode,
    Text,
    Newline

  # Hold two values: type: MarkdownTokenType, and xyzValue.
  # xyz is the particular type name.
  MarkdownTokenRef* = ref MarkdownToken
  MarkdownToken* = object
    pos: int
    len: int
    case type*: MarkdownTokenType
    of MarkdownTokenType.Header: headerVal*: Header
    of MarkdownTokenType.IndentedBlockCode: codeVal*: string
    of MarkdownTokenType.FencingBlockCode: fencingBlockCodeVal*: Fence
    of MarkdownTokenType.Text: textVal*: string
    of MarkdownTokenType.Newline: newlineVal*: string

var blockRules = @{
  MarkdownTokenType.Header: re"^ *(#{1,6}) *([^\n]+?) *#* *(?:\n+|$)",
  MarkdownTokenType.IndentedBlockCode: re"^(( {4}[^\n]+\n*)+)",
  MarkdownTokenType.FencingBlockCode: re"^( *`{3,} *([^`\s]+)? *\n([\s\S]+?)\s*`{3} *(\n+|$))",
  MarkdownTokenType.Text: re"^([^\n]+)",
  MarkdownTokenType.Newline: re"^(\n+)",
}.newTable

proc preprocessing*(doc: string): string =
  # Pre-processing the text
  result = doc.replace(re"\r\n|\r", "\n")
  result = result.replace(re"\t", "    ")
  result = result.replace("\u2424", " ")
  result = result.replace(re(r"^ +$", {RegexFlag.reMultiLine}), "")

proc escapeTag*(doc: string): string =
  # Replace `<` and `>` to HTML-safe characters.
  # Example:
  #   >>> escapeTag("<tag>")
  #   "&lt;tag&gt;"
  result = doc.replace("<", "&lt;")
  result = result.replace(">", "&gt;")

proc escapeQuote*(doc: string): string =
  # Replace `'` and `"` to HTML-safe characters.
  # Example:
  #   >>> escapeTag("'tag'")
  #   "&quote;tag&quote;"
  result = doc.replace("'", "&quote;")
  result = result.replace("\"", "&quote;")

proc escapeAmpersandChar*(doc: string): string =
  # Replace character `&` to HTML-safe characters.
  # Example:
  #   >>> escapeAmpersandChar("&amp;")
  #   &amp;amp;
  result = doc.replace("&", "&amp;")

let reAmpersandSeq = re"&(?!#?\w+;)"

proc escapeAmpersandSeq*(doc: string): string =
  # Replace `&` from a sequence of characters starting from it to HTML-safe characters.
  # It's useful to keep those have been escaped.
  # Example:
  #   >>> escapeAmpersandSeq("&") # In this case, it's like `escapeAmpersandChar`.
  #   "&"
  #   >>> escapeAmpersandSeq("&amp;") # In this case, we preserve that has escaped.
  #   "&amp;"
  result = doc.replace(sub=reAmpersandSeq, by="&amp;")

proc escapeCode*(doc: string): string =
  # Make code block in markdown document HTML-safe.
  result = doc.strip(leading=false, trailing=true).escapeTag.escapeAmpersandChar

proc findToken(doc: string, start: int, ruleType: MarkdownTokenType, regex: Regex): MarkdownTokenRef =
  # Find a markdown token from document `doc` at position `start`,
  # based on a rule type and regex rule.
  var matches: array[5, string]

  let size = doc.matchLen(regex, matches=matches, start=start)
  if size == -1:
    return nil

  case ruleType
  of MarkdownTokenType.Header:
    var val: Header
    val.level = matches[0].len
    val.doc = matches[1]
    result = MarkdownTokenRef(pos: start, len: size, type: MarkdownTokenType.Header, headerVal: val) 
  of MarkdownTokenType.Text:
    result = MarkdownTokenRef(pos: start, len: size, type: MarkdownTokenType.Text, textVal: matches[0])
  of MarkdownTokenType.Newline:
    if matches[0].len > 1:
      result = MarkdownTokenRef(pos: start, len: size, type: MarkdownTokenType.Newline, newlineVal: matches[0])
  of MarkdownTokenType.IndentedBlockCode:
    var code = matches[0].replace(re(r"^ {4}", {RegexFlag.reMultiLine}), "")
    result = MarkdownTokenRef(pos: start, len: size, type: MarkdownTokenType.IndentedBlockCode, codeVal: code)
  of MarkdownTokenType.FencingBlockCode:
    var val: Fence
    val.lang = matches[1]
    val.code = matches[2]
    result = MarkdownTokenRef(pos: start, len: size, type: MarkdownTokenType.FencingBlockCode, fencingBlockCodeVal: val)


iterator parseTokens(doc: string): MarkdownTokenRef =
  # Parse markdown document into a sequence of tokens.
  var n = 0
  block parseBlock:
    while n < doc.len:
      for ruleType, ruleRegex in blockRules:
        let token = findToken(doc, n, ruleType, ruleRegex)
        if token != nil:
          n += token.len
          yield token
          break parseBlock
      raise newException(MarkdownError, fmt"unknown block rule at position {n}.")


proc renderHeader*(header: Header): string =
  # Render header tag, for example, `<h1>`, `<h2>`, etc.
  # Example:
  #   >>> renderHeader("hello world", level=1)
  #   "<h1>hello world</h1>"
  result = fmt"<h{header.level}>{header.doc}</h{header.level}>"

proc renderText*(text: string): string =
  # Render text by escaping itself.
  result = text.escapeAmpersandSeq.escapeTag

proc renderNewline*(newline: string): string =
  # Render newline, which adds an empty string to the result.
  result = ""

proc renderFencingBlockCode*(fence: Fence): string =
  # Render fencing block code
  result = fmt("<pre><code lang=\"{fence.lang}\">{escapeCode(fence.code)}</code></pre>")

proc renderIndentedBlockCode*(code: string): string =
  # Render indented block code.
  # The code content will be escaped as it might contains HTML tags.
  # By default the indented block code doesn't support code highlight.
  result = fmt"<pre><code>{escapeCode(code)}</code></pre>"

proc renderToken(token: MarkdownTokenRef): string =
  # Render token.
  # This is a simple dispatcher function.
  case token.type
  of MarkdownTokenType.Header:
    result = renderHeader(token.headerVal)
  of MarkdownTokenType.Text:
    result = renderText(token.textVal)
  of MarkdownTokenType.Newline:
    result = renderNewline(token.newlineVal)
  of MarkdownTokenType.IndentedBlockCode:
    result = renderIndentedBlockCode(token.codeVal)
  of MarkdownTokenType.FencingBlockCode:
    result = renderFencingBlockCode(token.fencingBlockCodeVal)

# Turn markdown-formatted string into HTML-formatting string.
# By setting `escapse` to false, no HTML tag will be escaped.
proc markdown*(doc: string, escape: bool = true): string =
  for token in parsetokens(preprocessing(doc)):
      result &= rendertoken(token)