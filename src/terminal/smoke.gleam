import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/string
import support/file
import terminal/arkanoid
import terminal/pong

pub type SmokeReport {
  SmokeReport(
    example: String,
    ticks: Int,
    timeout_ms: Int,
    hash: String,
    score: String,
  )
}

pub fn play_smoke(
  example_path: String,
  ticks: Int,
  timeout_ms: Int,
) -> Result(SmokeReport, List(Diagnostic)) {
  let #(hash, score) = case string.contains(example_path, "arkanoid") {
    True -> {
      let state = arkanoid.run_ticks(ticks)
      #(arkanoid.snapshot_hash(state), arkanoid.score_text(state))
    }
    False -> {
      let state = pong.run_ticks(ticks)
      #(pong.snapshot_hash(state), pong.score_text(state))
    }
  }
  let report =
    SmokeReport(
      example: example_path,
      ticks: ticks,
      timeout_ms: timeout_ms,
      hash: hash,
      score: score,
    )
  use _ <- result_try(write_report(report))
  Ok(report)
}

fn write_report(report: SmokeReport) -> Result(Nil, List(Diagnostic)) {
  let path = case string.contains(report.example, "arkanoid") {
    True -> "build/reports/terminal/arkanoid.json"
    False -> "build/reports/terminal/pong.json"
  }
  case result_try_io(file.make_dir_all("build/reports/terminal")) {
    Error(diagnostics) -> Error(diagnostics)
    Ok(_) ->
      file.write_text_file(path, report_json(report))
      |> result_try_io
  }
}

fn report_json(report: SmokeReport) -> String {
  "{\n"
  <> "  \"example\": \""
  <> report.example
  <> "\",\n"
  <> "  \"ticks\": "
  <> int.to_string(report.ticks)
  <> ",\n"
  <> "  \"timeout_ms\": "
  <> int.to_string(report.timeout_ms)
  <> ",\n"
  <> "  \"score\": \""
  <> report.score
  <> "\",\n"
  <> "  \"hash\": \""
  <> report.hash
  <> "\"\n"
  <> "}\n"
}

fn result_try_io(result: Result(a, String)) -> Result(a, List(Diagnostic)) {
  case result {
    Ok(value) -> Ok(value)
    Error(message) ->
      Error([
        error(
          code: "terminal_report_write_failed",
          path: "build/reports/terminal/pong.json",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "terminal smoke reports must be writable",
        ),
      ])
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
