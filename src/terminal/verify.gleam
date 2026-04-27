import frontend/diagnostic.{type Diagnostic, error}
import gleam/list
import gleam/string
import support/file
import terminal/smoke

pub fn verify(
  example_path: String,
) -> Result(smoke.SmokeReport, List(Diagnostic)) {
  let expected_path = case string.contains(example_path, "arkanoid") {
    True -> example_path <> "/arkanoid.expected"
    False -> example_path <> "/pong.expected"
  }
  use expected_hash <- result_try(read_expected_hash(expected_path))
  use report <- result_try(smoke.play_smoke(example_path, 1000, 5000))
  case report.hash == expected_hash {
    True -> Ok(report)
    False ->
      Error([
        error(
          code: "terminal_hash_mismatch",
          path: expected_path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "terminal Pong hash did not match expected deterministic snapshot",
          help: "expected `"
            <> expected_hash
            <> "` but got `"
            <> report.hash
            <> "`",
        ),
      ])
  }
}

fn read_expected_hash(path: String) -> Result(String, List(Diagnostic)) {
  case file.read_text_file(path) {
    Ok(contents) ->
      case find_hash(contents) {
        Ok(hash) -> Ok(hash)
        Error(_) ->
          Error([
            error(
              code: "terminal_expected_hash_missing",
              path: path,
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: "terminal expected file is missing `hash_after_1000`",
              help: "record the deterministic Pong smoke hash",
            ),
          ])
      }
    Error(message) ->
      Error([
        error(
          code: "terminal_expected_read_failed",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "terminal examples must include an expected file",
        ),
      ])
  }
}

fn find_hash(contents: String) -> Result(String, Nil) {
  contents
  |> string.split(on: "\n")
  |> list.find_map(fn(line) {
    let trimmed = string.trim(line)
    case string.starts_with(trimmed, "hash_after_1000 = ") {
      True -> Ok(trimmed |> string.drop_start(up_to: 18) |> trim_quotes)
      False -> Error(Nil)
    }
  })
}

fn trim_quotes(value: String) -> String {
  case string.starts_with(value, "\"") && string.ends_with(value, "\"") {
    True -> value |> string.drop_start(up_to: 1) |> string.drop_end(up_to: 1)
    False -> value
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
