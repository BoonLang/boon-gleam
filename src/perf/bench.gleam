import backend/postgres
import backend/session.{type StoreKind}
import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import project/loader
import support/file
import support/os
import terminal/arkanoid
import terminal/pong

pub type BenchReport {
  BenchReport(
    command: String,
    example: String,
    target: String,
    samples: List(Int),
    p50: Int,
    p95: Int,
    max: Int,
    environment: String,
  )
}

pub fn local(
  example_path: String,
  events: Int,
  ticks: Int,
  report_path: String,
) -> Result(BenchReport, List(Diagnostic)) {
  let target = case ticks > 0 {
    True -> "terminal"
    False -> "generated-update"
  }
  use samples <- result_try(case ticks > 0 {
    True -> terminal_samples(example_path, ticks)
    False -> event_samples(example_path, max_positive(events, 100))
  })
  let report = build_report("bench", example_path, target, samples)
  use _ <- result_try(write_report(
    report,
    chosen_report_path(report_path, example_path, "bench"),
  ))
  Ok(report)
}

pub fn backend(
  example_path: String,
  events: Int,
  store: StoreKind,
  report_path: String,
) -> Result(BenchReport, List(Diagnostic)) {
  let event_count = max_positive(events, 100)
  use samples <- result_try(backend_samples(example_path, event_count, store))
  let report =
    build_report(
      "bench-backend",
      example_path,
      "backend-" <> session.store_name(store),
      samples,
    )
  use _ <- result_try(write_report(
    report,
    chosen_report_path(report_path, example_path, "bench-backend"),
  ))
  Ok(report)
}

fn backend_samples(
  example_path: String,
  event_count: Int,
  store: StoreKind,
) -> Result(List(Int), List(Diagnostic)) {
  case session.is_postgres(store) {
    False -> session_samples(example_path, store, event_count)
    True ->
      case postgres.require_database_url() {
        Error(diagnostics) -> Error(diagnostics)
        Ok(database_url) ->
          postgres.benchmark_events(example_path, database_url, event_count)
      }
  }
}

fn event_samples(
  example_path: String,
  events: Int,
) -> Result(List(Int), List(Diagnostic)) {
  use project <- result_try(loader.load(example_path))
  use _program <- result_try(loader.parse_project(project))
  session_samples(example_path, session.Memory, events)
}

fn session_samples(
  example_path: String,
  store: StoreKind,
  events: Int,
) -> Result(List(Int), List(Diagnostic)) {
  let started = session.start(example_path, store, "bench snapshot")
  session_sample_loop(started, events, 1, [])
}

fn session_sample_loop(
  backend_session: session.BackendSession,
  remaining: Int,
  event_index: Int,
  samples: List(Int),
) -> Result(List(Int), List(Diagnostic)) {
  case remaining <= 0 {
    True -> Ok(list.reverse(samples))
    False -> {
      let started_at = os.monotonic_microsecond()
      let accepted =
        session.accept_event(
          backend_session,
          "bench-event-" <> int.to_string(event_index),
          backend_session.revision,
          "bench",
        )
      let finished_at = os.monotonic_microsecond()
      case accepted {
        Ok(#(next_session, _result)) ->
          session_sample_loop(next_session, remaining - 1, event_index + 1, [
            finished_at - started_at,
            ..samples
          ])
        Error(store_error) -> Error([store_diagnostic(store_error)])
      }
    }
  }
}

fn terminal_samples(
  example_path: String,
  ticks: Int,
) -> Result(List(Int), List(Diagnostic)) {
  case string.contains(example_path, "arkanoid") {
    True -> Ok(arkanoid_sample_loop(arkanoid.init(), ticks, []))
    False -> Ok(pong_sample_loop(pong.init(), ticks, []))
  }
}

fn pong_sample_loop(
  state: pong.PongState,
  remaining: Int,
  samples: List(Int),
) -> List(Int) {
  case remaining <= 0 {
    True -> list.reverse(samples)
    False -> {
      let started_at = os.monotonic_microsecond()
      let next = pong.tick(state)
      let _hash = pong.snapshot_hash(next)
      let finished_at = os.monotonic_microsecond()
      pong_sample_loop(next, remaining - 1, [
        finished_at - started_at,
        ..samples
      ])
    }
  }
}

fn arkanoid_sample_loop(
  state: arkanoid.ArkanoidState,
  remaining: Int,
  samples: List(Int),
) -> List(Int) {
  case remaining <= 0 {
    True -> list.reverse(samples)
    False -> {
      let started_at = os.monotonic_microsecond()
      let next = arkanoid.tick(state)
      let _hash = arkanoid.snapshot_hash(next)
      let finished_at = os.monotonic_microsecond()
      arkanoid_sample_loop(next, remaining - 1, [
        finished_at - started_at,
        ..samples
      ])
    }
  }
}

fn build_report(
  command: String,
  example: String,
  target: String,
  samples: List(Int),
) -> BenchReport {
  let sorted = list.sort(samples, compare_int)
  BenchReport(
    command: command,
    example: example,
    target: target,
    samples: samples,
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    max: max_sample(sorted),
    environment: os.runtime_summary(),
  )
}

fn percentile(sorted: List(Int), percent: Int) -> Int {
  let count = list.length(sorted)
  case count <= 0 {
    True -> 0
    False -> {
      let index = { { count * percent } + 99 } / 100 - 1
      nth(sorted, clamp(index, 0, count - 1), 0)
    }
  }
}

fn max_sample(sorted: List(Int)) -> Int {
  case sorted {
    [] -> 0
    [value] -> value
    [_first, ..rest] -> max_sample(rest)
  }
}

fn nth(values: List(Int), index: Int, fallback: Int) -> Int {
  case values, index {
    [], _ -> fallback
    [value, ..], 0 -> value
    [_value, ..rest], _ -> nth(rest, index - 1, fallback)
  }
}

fn compare_int(left: Int, right: Int) -> order.Order {
  case left < right {
    True -> order.Lt
    False ->
      case left > right {
        True -> order.Gt
        False -> order.Eq
      }
  }
}

fn max_positive(value: Int, fallback: Int) -> Int {
  case value > 0 {
    True -> value
    False -> fallback
  }
}

fn clamp(value: Int, minimum: Int, maximum: Int) -> Int {
  case value < minimum {
    True -> minimum
    False ->
      case value > maximum {
        True -> maximum
        False -> value
      }
  }
}

fn chosen_report_path(
  requested: String,
  example_path: String,
  command: String,
) -> String {
  case string.trim(requested) {
    "" ->
      "build/reports/perf/"
      <> session.project_id(example_path)
      <> "-"
      <> command
      <> ".json"
    path -> path
  }
}

fn write_report(
  report: BenchReport,
  path: String,
) -> Result(Nil, List(Diagnostic)) {
  case result_try_io(file.make_dir_all("build/reports/perf")) {
    Error(diagnostics) -> Error(diagnostics)
    Ok(_) ->
      file.write_text_file(path, report_json(report))
      |> result_try_io
  }
}

fn report_json(report: BenchReport) -> String {
  "{\n"
  <> "  \"command\": \""
  <> escape_json(report.command)
  <> "\",\n"
  <> "  \"example\": \""
  <> escape_json(report.example)
  <> "\",\n"
  <> "  \"target\": \""
  <> escape_json(report.target)
  <> "\",\n"
  <> "  \"samples\": ["
  <> string.join(list.map(report.samples, int.to_string), with: ", ")
  <> "],\n"
  <> "  \"sample_unit\": \"microseconds\",\n"
  <> "  \"p50\": "
  <> int.to_string(report.p50)
  <> ",\n"
  <> "  \"p95\": "
  <> int.to_string(report.p95)
  <> ",\n"
  <> "  \"max\": "
  <> int.to_string(report.max)
  <> ",\n"
  <> "  \"environment\": \""
  <> escape_json(report.environment)
  <> "\"\n"
  <> "}\n"
}

fn store_diagnostic(store_error: session.StoreError) -> Diagnostic {
  error(
    code: "bench_store_failed",
    path: "bench",
    line: 1,
    column: 1,
    span_start: 0,
    span_end: 0,
    message: store_error_message(store_error),
    help: "performance measurement must run against an accepting session",
  )
}

fn store_error_message(store_error: session.StoreError) -> String {
  case store_error {
    session.RevisionConflict(current_revision) ->
      "revision conflict at " <> int.to_string(current_revision)
    session.StoreUnavailable(message) -> message
  }
}

fn escape_json(value: String) -> String {
  value
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: "\"", with: "\\\"")
}

fn result_try_io(result: Result(a, String)) -> Result(a, List(Diagnostic)) {
  case result {
    Ok(value) -> Ok(value)
    Error(message) ->
      Error([
        error(
          code: "perf_report_write_failed",
          path: "build/reports/perf",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "performance reports must be writable",
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
    Error(diagnostics) -> Error(diagnostics)
  }
}
