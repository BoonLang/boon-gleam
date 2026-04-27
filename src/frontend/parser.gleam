import frontend/ast.{
  type Definition, type Expression, type NamedArgument, type Program,
  BoolLiteral, Call, Definition, FieldAccess, IdentifierRef, IntLiteral,
  ListLiteral, NamedArgument, PipeCall, Program, RawExpression, Record,
  StringLiteral, TextLiteral,
}
import frontend/diagnostic.{type Diagnostic, error}
import frontend/token.{
  type Span, type Token, type TokenKind, Colon, Comma, Dot, EndOfFile,
  Identifier, IntToken, LeftBrace, LeftBracket, LeftParen, Pipe, RightBrace,
  RightBracket, RightParen, Span, StringToken, Token,
}
import gleam/list
import gleam/string

pub fn parse(
  path: String,
  tokens: List(Token),
) -> Result(Program, List(Diagnostic)) {
  parse_definitions(path, tokens, [])
}

fn parse_definitions(
  path: String,
  tokens: List(Token),
  definitions: List(Definition),
) -> Result(Program, List(Diagnostic)) {
  case tokens {
    [] -> Ok(Program(list.reverse(definitions)))
    [Token(EndOfFile, _, _), ..] -> Ok(Program(list.reverse(definitions)))
    [Token(Identifier(name), _, span), Token(Colon, _, _), ..rest] -> {
      let #(body, remaining) = split_definition_body(rest, [])
      let value = parse_definition_body(path, body)
      parse_definitions(path, remaining, [
        Definition(name, value, span),
        ..definitions
      ])
    }
    [token, ..] ->
      Error([
        diagnostic(
          path,
          token.span,
          "expected_definition",
          "expected a top-level definition in the form `name: expression`",
        ),
      ])
  }
}

fn split_definition_body(
  tokens: List(Token),
  acc: List(Token),
) -> #(List(Token), List(Token)) {
  case tokens {
    [] -> #(list.reverse(acc), [])
    [Token(EndOfFile, _, _), ..] -> #(list.reverse(acc), tokens)
    [Token(Identifier(_), _, span), Token(Colon, _, _), ..]
      if span.column == 1
    -> #(list.reverse(acc), tokens)
    [token, ..rest] -> split_definition_body(rest, [token, ..acc])
  }
}

fn parse_definition_body(path: String, body: List(Token)) -> Expression {
  let body_with_eof =
    list.append(body, [
      Token(EndOfFile, "", Span(1, 1, 0, 0)),
    ])
  case parse_expression(path, body_with_eof) {
    Ok(#(expression, [Token(EndOfFile, _, _), ..])) -> expression
    _ -> RawExpression(tokens_to_text(body))
  }
}

fn tokens_to_text(tokens: List(Token)) -> String {
  tokens
  |> list.map(fn(token) { token.lexeme })
  |> string.join(with: " ")
}

fn parse_expression(
  path: String,
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), List(Diagnostic)) {
  use parsed <- result_try(parse_postfix(path, tokens))
  let #(left, rest) = parsed

  case rest {
    [Token(Pipe, _, _), ..pipe_rest] -> {
      use right <- result_try(parse_postfix(path, pipe_rest))
      let #(call, remaining) = right
      Ok(#(PipeCall(left, call), remaining))
    }
    _ -> Ok(#(left, rest))
  }
}

fn parse_postfix(
  path: String,
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), List(Diagnostic)) {
  use parsed <- result_try(parse_primary(path, tokens))
  parse_postfix_loop(parsed)
}

fn parse_postfix_loop(
  parsed: #(Expression, List(Token)),
) -> Result(#(Expression, List(Token)), List(Diagnostic)) {
  let #(receiver, tokens) = parsed
  case tokens {
    [Token(Dot, _, _), Token(Identifier(field), _, _), ..rest] ->
      parse_postfix_loop(#(FieldAccess(receiver, field), rest))
    _ -> Ok(parsed)
  }
}

fn parse_primary(
  path: String,
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), List(Diagnostic)) {
  case tokens {
    [Token(IntToken(value), _, _), ..rest] -> Ok(#(IntLiteral(value), rest))
    [Token(StringToken(value), _, _), ..rest] ->
      Ok(#(StringLiteral(value), rest))
    [Token(Identifier("True"), _, _), ..rest] -> Ok(#(BoolLiteral(True), rest))
    [Token(Identifier("False"), _, _), ..rest] ->
      Ok(#(BoolLiteral(False), rest))
    [Token(Identifier("SOURCE"), _, span), ..] ->
      Error([
        diagnostic(
          path,
          span,
          "unsupported_source_marker",
          "SOURCE is not accepted by boon-gleam v0/v1; use LINK for the pinned corpus",
        ),
      ])
    [Token(Identifier("TEXT"), _, _), Token(LeftBrace, _, _), ..rest] ->
      parse_text(path, rest, [])
    [Token(Identifier(name), _, _), Token(LeftParen, _, _), ..rest] -> {
      use parsed <- result_try(
        parse_named_arguments(path, rest, RightParen, []),
      )
      let #(arguments, remaining) = parsed
      Ok(#(Call(name, arguments), remaining))
    }
    [Token(Identifier(name), _, _), Token(LeftBrace, _, _), ..rest] -> {
      use parsed <- result_try(
        parse_named_arguments(path, rest, RightBrace, []),
      )
      let #(fields, remaining) = parsed
      Ok(#(Record(name, fields), remaining))
    }
    [Token(Identifier(name), _, _), ..rest] -> Ok(#(IdentifierRef(name), rest))
    [Token(LeftBracket, _, _), ..rest] -> parse_list(path, rest, [])
    [token, ..] ->
      Error([
        diagnostic(
          path,
          token.span,
          "expected_expression",
          "expected an expression",
        ),
      ])
    [] ->
      Error([
        error(
          code: "unexpected_eof",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "unexpected end of file",
          help: "add an expression",
        ),
      ])
  }
}

fn parse_text(
  path: String,
  tokens: List(Token),
  acc: List(String),
) -> Result(#(Expression, List(Token)), List(Diagnostic)) {
  case tokens {
    [Token(RightBrace, _, _), ..rest] ->
      Ok(#(TextLiteral(acc |> list.reverse |> string.join(with: " ")), rest))
    [Token(EndOfFile, _, span), ..] ->
      Error([
        diagnostic(path, span, "unterminated_text", "TEXT block is missing `}`"),
      ])
    [Token(_, lexeme, _), ..rest] -> parse_text(path, rest, [lexeme, ..acc])
    [] ->
      Error([
        error(
          code: "unterminated_text",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "TEXT block is missing `}`",
          help: "close the TEXT block",
        ),
      ])
  }
}

fn parse_list(
  path: String,
  tokens: List(Token),
  acc: List(Expression),
) -> Result(#(Expression, List(Token)), List(Diagnostic)) {
  case tokens {
    [Token(RightBracket, _, _), ..rest] ->
      Ok(#(ListLiteral(list.reverse(acc)), rest))
    _ -> {
      use parsed <- result_try(parse_expression(path, tokens))
      let #(item, rest) = parsed
      case rest {
        [Token(Comma, _, _), ..after_comma] ->
          parse_list(path, after_comma, [item, ..acc])
        [Token(RightBracket, _, _), ..after] ->
          Ok(#(ListLiteral(list.reverse([item, ..acc])), after))
        [token, ..] ->
          Error([
            diagnostic(
              path,
              token.span,
              "expected_list_separator",
              "expected `,` or `]` in list",
            ),
          ])
        [] ->
          Error([
            error(
              code: "unterminated_list",
              path: path,
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: "list is missing `]`",
              help: "close the list",
            ),
          ])
      }
    }
  }
}

fn parse_named_arguments(
  path: String,
  tokens: List(Token),
  terminator: TokenKind,
  acc: List(NamedArgument),
) -> Result(#(List(NamedArgument), List(Token)), List(Diagnostic)) {
  case tokens {
    [Token(kind, _, _), ..rest] if kind == terminator ->
      Ok(#(list.reverse(acc), rest))
    [Token(Identifier(name), _, _), Token(Colon, _, _), ..rest] -> {
      use parsed <- result_try(parse_expression(path, rest))
      let #(value, remaining) = parsed
      case remaining {
        [Token(Comma, _, _), ..after_comma] ->
          parse_named_arguments(path, after_comma, terminator, [
            NamedArgument(name, value),
            ..acc
          ])
        [Token(kind, _, _), ..after] if kind == terminator ->
          Ok(#(list.reverse([NamedArgument(name, value), ..acc]), after))
        [token, ..] ->
          Error([
            diagnostic(
              path,
              token.span,
              "expected_argument_separator",
              "expected `,` or closing delimiter in argument list",
            ),
          ])
        [] ->
          Error([
            error(
              code: "unterminated_arguments",
              path: path,
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: "argument list is missing a closing delimiter",
              help: "close the argument list",
            ),
          ])
      }
    }
    [token, ..] ->
      Error([
        diagnostic(
          path,
          token.span,
          "expected_named_argument",
          "expected a named argument in the form `name: expression`",
        ),
      ])
    [] ->
      Error([
        error(
          code: "unterminated_arguments",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "argument list is missing a closing delimiter",
          help: "close the argument list",
        ),
      ])
  }
}

fn diagnostic(
  path: String,
  span: Span,
  code: String,
  message: String,
) -> Diagnostic {
  case span {
    Span(line, column, start, end) ->
      error(
        code: code,
        path: path,
        line: line,
        column: column,
        span_start: start,
        span_end: end,
        message: message,
        help: "see BOON_GLEAM_IMPLEMENTATION_PLAN.md for the supported phase syntax",
      )
  }
}

fn result_try(
  result: Result(a, List(Diagnostic)),
  next: fn(a) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
