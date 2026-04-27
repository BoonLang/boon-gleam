import frontend/diagnostic.{type Diagnostic}
import frontend/token.{
  type Token, type TokenKind, Colon, Comma, Dot, EndOfFile, Identifier, IntToken,
  LeftBrace, LeftBracket, LeftParen, Pipe, RightBrace, RightBracket, RightParen,
  Span, StringToken, Token,
}
import gleam/int
import gleam/list
import gleam/string

type Cursor {
  Cursor(
    path: String,
    chars: List(String),
    line: Int,
    column: Int,
    offset: Int,
    tokens: List(Token),
  )
}

pub fn lex(
  path: String,
  source: String,
) -> Result(List(Token), List(Diagnostic)) {
  let cursor =
    Cursor(
      path:,
      chars: string.to_graphemes(source),
      line: 1,
      column: 1,
      offset: 0,
      tokens: [],
    )

  Ok(scan(cursor))
}

fn scan(cursor: Cursor) -> List(Token) {
  case cursor.chars {
    [] -> {
      let eof_span =
        Span(
          line: cursor.line,
          column: cursor.column,
          start: cursor.offset,
          end: cursor.offset,
        )
      list.reverse([Token(EndOfFile, "", eof_span), ..cursor.tokens])
    }
    ["\n", ..rest] ->
      scan(
        Cursor(
          ..cursor,
          chars: rest,
          line: cursor.line + 1,
          column: 1,
          offset: cursor.offset + 1,
        ),
      )
    ["-", "-", ..rest] ->
      skip_comment(
        Cursor(
          ..cursor,
          chars: rest,
          column: cursor.column + 2,
          offset: cursor.offset + 2,
        ),
      )
    ["(", ..rest] -> push_single(cursor, rest, LeftParen, "(")
    [")", ..rest] -> push_single(cursor, rest, RightParen, ")")
    ["{", ..rest] -> push_single(cursor, rest, LeftBrace, "{")
    ["}", ..rest] -> push_single(cursor, rest, RightBrace, "}")
    ["[", ..rest] -> push_single(cursor, rest, LeftBracket, "[")
    ["]", ..rest] -> push_single(cursor, rest, RightBracket, "]")
    [":", ..rest] -> push_single(cursor, rest, Colon, ":")
    [",", ..rest] -> push_single(cursor, rest, Comma, ",")
    [".", ..rest] -> push_single(cursor, rest, Dot, ".")
    ["|", ">", ..rest] -> {
      let span =
        Span(
          line: cursor.line,
          column: cursor.column,
          start: cursor.offset,
          end: cursor.offset + 2,
        )
      scan(
        Cursor(
          ..cursor,
          chars: rest,
          column: cursor.column + 2,
          offset: cursor.offset + 2,
          tokens: [Token(Pipe, "|>", span), ..cursor.tokens],
        ),
      )
    }
    ["\"", ..rest] -> read_string(cursor, rest, [])
    [char, ..rest] ->
      case is_whitespace(char) {
        True ->
          scan(
            Cursor(
              ..cursor,
              chars: rest,
              column: cursor.column + 1,
              offset: cursor.offset + 1,
            ),
          )
        False -> read_word(cursor, [])
      }
  }
}

fn push_single(
  cursor: Cursor,
  rest: List(String),
  kind: TokenKind,
  lexeme: String,
) -> List(Token) {
  let span =
    Span(
      line: cursor.line,
      column: cursor.column,
      start: cursor.offset,
      end: cursor.offset + 1,
    )
  scan(
    Cursor(
      ..cursor,
      chars: rest,
      column: cursor.column + 1,
      offset: cursor.offset + 1,
      tokens: [Token(kind, lexeme, span), ..cursor.tokens],
    ),
  )
}

fn skip_comment(cursor: Cursor) -> List(Token) {
  case cursor.chars {
    [] -> scan(cursor)
    ["\n", ..] -> scan(cursor)
    [_, ..rest] ->
      skip_comment(
        Cursor(
          ..cursor,
          chars: rest,
          column: cursor.column + 1,
          offset: cursor.offset + 1,
        ),
      )
  }
}

fn read_string(
  cursor: Cursor,
  rest: List(String),
  acc: List(String),
) -> List(Token) {
  case rest {
    [] -> {
      let value = acc |> list.reverse |> string.join(with: "")
      let span =
        Span(
          line: cursor.line,
          column: cursor.column,
          start: cursor.offset,
          end: cursor.offset + string.length(value) + 1,
        )
      list.reverse([Token(StringToken(value), value, span), ..cursor.tokens])
    }
    ["\"", ..after] -> {
      let value = acc |> list.reverse |> string.join(with: "")
      let width = string.length(value) + 2
      let span =
        Span(
          line: cursor.line,
          column: cursor.column,
          start: cursor.offset,
          end: cursor.offset + width,
        )
      scan(
        Cursor(
          ..cursor,
          chars: after,
          column: cursor.column + width,
          offset: cursor.offset + width,
          tokens: [Token(StringToken(value), value, span), ..cursor.tokens],
        ),
      )
    }
    [char, ..after] -> read_string(cursor, after, [char, ..acc])
  }
}

fn read_word(cursor: Cursor, acc: List(String)) -> List(Token) {
  case cursor.chars {
    [] -> finish_word(cursor, acc, [])
    [char, ..rest] ->
      case is_word_delimiter(char) {
        True -> finish_word(cursor, acc, cursor.chars)
        False ->
          read_word(
            Cursor(
              ..cursor,
              chars: rest,
              column: cursor.column + 1,
              offset: cursor.offset + 1,
            ),
            [char, ..acc],
          )
      }
  }
}

fn finish_word(
  cursor: Cursor,
  acc: List(String),
  remaining: List(String),
) -> List(Token) {
  let lexeme = acc |> list.reverse |> string.join(with: "")
  let width = string.length(lexeme)
  let start = cursor.offset - width
  let span =
    Span(
      line: cursor.line,
      column: cursor.column - width,
      start: start,
      end: cursor.offset,
    )

  let token_kind = case int.parse(lexeme) {
    Ok(value) -> IntToken(value)
    Error(_) -> Identifier(lexeme)
  }

  scan(
    Cursor(..cursor, chars: remaining, tokens: [
      Token(token_kind, lexeme, span),
      ..cursor.tokens
    ]),
  )
}

fn is_whitespace(char: String) -> Bool {
  char == " " || char == "\t" || char == "\r"
}

fn is_word_delimiter(char: String) -> Bool {
  is_whitespace(char)
  || char == "\n"
  || char == "("
  || char == ")"
  || char == "{"
  || char == "}"
  || char == "["
  || char == "]"
  || char == ":"
  || char == ","
  || char == "."
  || char == "\""
  || char == "|"
}
