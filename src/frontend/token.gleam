pub type Span {
  Span(line: Int, column: Int, start: Int, end: Int)
}

pub type TokenKind {
  Identifier(String)
  IntToken(Int)
  StringToken(String)
  Colon
  Comma
  Dot
  LeftParen
  RightParen
  LeftBrace
  RightBrace
  LeftBracket
  RightBracket
  Pipe
  EndOfFile
}

pub type Token {
  Token(kind: TokenKind, lexeme: String, span: Span)
}
