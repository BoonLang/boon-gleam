import backend/durability
import backend/postgres
import backend/session
import backend/smoke as backend_smoke
import codegen/core as core_codegen
import frontend/ast
import frontend/diagnostic
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import lowering/pipeline
import perf/bench as perf_bench
import project/importer
import project/loader
import support/argv
import support/file
import support/os
import terminal/play as terminal_play
import terminal/smoke as terminal_smoke
import terminal/verify as terminal_verify
import verify/all as verify_all
import verify/report as verify_report
import verify/runner
import web/lustre_client

pub fn main() -> Nil {
  case argv.start_arguments() {
    [] -> print_help()
    ["help"] -> print_help()
    ["--help"] -> print_help()
    ["-h"] -> print_help()
    ["import-upstream", ..rest] -> import_upstream(rest)
    ["manifest", ..] -> manifest()
    ["compile", path, ..] -> compile(path)
    ["codegen", path, ..rest] -> codegen(path, rest)
    ["tui", ..] -> play("examples/terminal/pong")
    ["play", path, ..] -> play(path)
    ["play-smoke", path, ..rest] -> play_smoke(path, rest)
    ["serve", path, ..rest] -> serve(path, rest)
    ["serve-smoke", path, ..rest] -> serve_smoke(path, rest)
    ["bench", path, ..rest] -> bench(path, rest)
    ["bench-backend", path, ..rest] -> bench_backend(path, rest)
    ["store", "setup-postgres", ..rest] -> setup_postgres(rest)
    ["verify-backend", path, ..rest] -> verify_backend(path, rest)
    ["verify-durability", path, ..rest] -> verify_durability(path, rest)
    ["web", path, ..rest] -> web(path, rest)
    ["verify-all", ..] -> verify_all()
    ["verify", path, ..rest] -> verify_command(path, rest)
    [command, ..] -> print_not_implemented(command)
  }
}

fn play(path: String) -> Nil {
  case terminal_play.play(path) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(_) -> Nil
  }
}

fn verify_all() -> Nil {
  case verify_all.run() {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) ->
      io.println(
        "verify-all semantic="
        <> int.to_string(report.semantic_count)
        <> " terminal="
        <> int.to_string(report.terminal_count),
      )
  }
}

fn web(path: String, args: List(String)) -> Nil {
  let mode = flag_string(args, "--mode", "durable-client")
  case lustre_client.build(path, mode) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) ->
      io.println(
        "web "
        <> report.example
        <> " mode="
        <> report.mode
        <> " output="
        <> report.output_path,
      )
  }
}

fn setup_postgres(args: List(String)) -> Nil {
  let database_url = flag_string(args, "--database-url", "")
  case postgres.setup(database_url) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(_) -> io.println("postgres schema ready")
  }
}

fn bench(path: String, args: List(String)) -> Nil {
  let events = flag_int(args, "--events", 100)
  let ticks = flag_int(args, "--ticks", 0)
  let report_path = flag_string(args, "--report", "")
  case perf_bench.local(path, events, ticks, report_path) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) ->
      io.println(
        "bench "
        <> report.example
        <> " target="
        <> report.target
        <> " samples="
        <> int.to_string(list.length(report.samples))
        <> " p95_us="
        <> int.to_string(report.p95),
      )
  }
}

fn bench_backend(path: String, args: List(String)) -> Nil {
  let events = flag_int(args, "--events", 100)
  let store = session.parse_store(flag_string(args, "--store", "local"))
  let report_path = flag_string(args, "--report", "")
  case perf_bench.backend(path, events, store, report_path) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) ->
      io.println(
        "bench-backend "
        <> report.example
        <> " target="
        <> report.target
        <> " samples="
        <> int.to_string(list.length(report.samples))
        <> " p95_us="
        <> int.to_string(report.p95),
      )
  }
}

fn verify_durability(path: String, args: List(String)) -> Nil {
  let store = session.parse_store(flag_string(args, "--store", "local"))
  case session.is_postgres(store) {
    True ->
      case postgres.require_database_url() {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(database_url) ->
          case postgres.verify_session(path, database_url) {
            Error(diagnostics) -> fail_with_diagnostics(diagnostics)
            Ok(_) -> verify_durability_with_store(path, store)
          }
      }
    False -> verify_durability_with_store(path, store)
  }
}

fn verify_durability_with_store(path: String, store: session.StoreKind) -> Nil {
  case durability.verify(path, store) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) ->
      io.println(
        "verified durability "
        <> report.example
        <> " events="
        <> int.to_string(report.events_replayed),
      )
  }
}

fn serve_smoke(path: String, args: List(String)) -> Nil {
  let store = session.parse_store(flag_string(args, "--store", "memory"))
  let port = flag_int(args, "--port", 8080)
  let timeout_ms = flag_int(args, "--timeout-ms", 5000)
  case backend_smoke.serve_smoke(path, store, port, timeout_ms) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) ->
      io.println(
        "serve-smoke "
        <> report.example
        <> " store="
        <> session.store_name(report.store)
        <> " revision="
        <> int.to_string(report.revision),
      )
  }
}

fn serve(path: String, args: List(String)) -> Nil {
  let store = session.parse_store(flag_string(args, "--store", "memory"))
  let port = flag_int(args, "--port", 8080)
  case backend_smoke.serve(path, store, port) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(_) -> Nil
  }
}

fn verify_backend(path: String, args: List(String)) -> Nil {
  let store = session.parse_store(flag_string(args, "--store", "memory"))
  case session.is_postgres(store) {
    True ->
      case postgres.require_database_url() {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(database_url) ->
          case postgres.verify_session(path, database_url) {
            Error(diagnostics) -> fail_with_diagnostics(diagnostics)
            Ok(_) -> verify_backend_with_store(path, store)
          }
      }
    False -> verify_backend_with_store(path, store)
  }
}

fn verify_backend_with_store(path: String, store: session.StoreKind) -> Nil {
  case backend_smoke.verify_backend(path, store) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) ->
      io.println(
        "verified backend "
        <> report.example
        <> " store="
        <> session.store_name(report.store)
        <> " revision="
        <> int.to_string(report.revision),
      )
  }
}

fn play_smoke(path: String, args: List(String)) -> Nil {
  let ticks = flag_int(args, "--ticks", 1000)
  let timeout_ms = flag_int(args, "--timeout-ms", 5000)
  case terminal_smoke.play_smoke(path, ticks, timeout_ms) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) ->
      io.println(
        "play-smoke "
        <> report.example
        <> ": ticks="
        <> int.to_string(report.ticks)
        <> " hash="
        <> report.hash,
      )
  }
}

fn verify_command(path: String, args: List(String)) -> Nil {
  let target = flag_string(args, "--target", "semantic")
  case target {
    "terminal" -> verify_terminal(path, flag_string(args, "--report", ""))
    _ -> verify(path, flag_string(args, "--report", ""))
  }
}

fn verify_terminal(path: String, report_path: String) -> Nil {
  case terminal_verify.verify(path) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) -> {
      maybe_write_report(report_path, terminal_report_json(report))
      io.println(
        "verified terminal "
        <> report.example
        <> ": ticks="
        <> int.to_string(report.ticks)
        <> " hash="
        <> report.hash,
      )
    }
  }
}

fn flag_int(args: List(String), name: String, default: Int) -> Int {
  case args {
    [] -> default
    [flag, value, ..rest] ->
      case flag == name {
        True ->
          case int.parse(value) {
            Ok(parsed) -> parsed
            Error(_) -> default
          }
        False -> flag_int([value, ..rest], name, default)
      }
    [_] -> default
  }
}

fn flag_string(args: List(String), name: String, default: String) -> String {
  case args {
    [] -> default
    [flag, value, ..rest] ->
      case flag == name {
        True -> value
        False -> flag_string([value, ..rest], name, default)
      }
    [_] -> default
  }
}

fn print_help() -> Nil {
  io.println("boongleam - Gleam implementation and codegen backend for Boon")
  io.println("")
  io.println("Usage:")
  io.println("  gleam run -- help")
  io.println("  gleam run -- <command> [options]")
  io.println("")
  io.println("Implemented:")
  io.println("  help")
  io.println("  import-upstream")
  io.println("  manifest")
  io.println("  compile")
  io.println("  codegen")
  io.println("  verify")
  io.println("  verify-all")
  io.println("  verify-backend")
  io.println("  verify-durability")
  io.println("  tui")
  io.println("  play")
  io.println("  play-smoke")
  io.println("  serve")
  io.println("  serve-smoke")
  io.println("  bench")
  io.println("  bench-backend")
  io.println("  web")
  io.println("  store setup-postgres")
}

fn import_upstream(args: List(String)) -> Nil {
  let source = flag_string(args, "--source", "")
  let out = flag_string(args, "--out", "examples/upstream")
  case string.trim(source) {
    "" ->
      fail_with_diagnostics([
        diagnostic.error(
          code: "import_source_required",
          path: "import-upstream",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "missing --source PATH",
          help: "run `gleam run -- import-upstream --source PATH --out examples/upstream`",
        ),
      ])
    _ ->
      case importer.import_upstream(source, out) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(report) -> {
          io.println(importer.summary(report))
          manifest()
        }
      }
  }
}

fn print_not_implemented(command: String) -> Nil {
  io.println("boongleam: unknown command: " <> command)
  io.println("Run `gleam run -- help` for the implemented CLI surface.")
  os.exit(1)
}

fn compile(path: String) -> Nil {
  case loader.load(path) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(project) ->
      case loader.parse_project(project) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(program) -> {
          io.println(
            "compiled "
            <> path
            <> ": "
            <> int.to_string(ast.definition_count(program))
            <> " definitions",
          )
          Nil
        }
      }
  }
}

fn manifest() -> Nil {
  case validate_manifest() {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(#(examples, ignored)) ->
      io.println(
        "manifest examples="
        <> int.to_string(examples)
        <> " ignored="
        <> int.to_string(ignored),
      )
  }
}

fn validate_manifest() -> Result(#(Int, Int), List(diagnostic.Diagnostic)) {
  let manifest_path = "fixtures/corpus_manifest.json"
  case file.read_text_file(manifest_path) {
    Error(message) ->
      Error([
        diagnostic.error(
          code: "manifest_read_failed",
          path: manifest_path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "fixtures/corpus_manifest.json is required by the source corpus contract",
        ),
      ])
    Ok(contents) ->
      case manifest_has_required_metadata(contents) {
        False ->
          Error([
            diagnostic.error(
              code: "manifest_invalid",
              path: manifest_path,
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: "manifest is missing schema_version, sources, examples, or ignored metadata",
              help: "regenerate the corpus manifest from the pinned Boon corpus",
            ),
          ])
        True -> validate_manifest_paths(contents)
      }
  }
}

fn validate_manifest_paths(
  contents: String,
) -> Result(#(Int, Int), List(diagnostic.Diagnostic)) {
  let missing =
    manifest_paths()
    |> list.filter(fn(path) { !file.is_directory(path) })
  case missing {
    [] -> {
      let examples = count_occurrences(contents, "\"local_path\"")
      let ignored = count_occurrences(contents, "\"ignored_reason\"") - examples
      Ok(#(examples, ignored))
    }
    [path, ..] ->
      Error([
        diagnostic.error(
          code: "manifest_path_missing",
          path: "fixtures/corpus_manifest.json",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "manifest path does not exist: " <> path,
          help: "import-upstream must preserve the manifest local_path entries",
        ),
      ])
  }
}

fn manifest_has_required_metadata(contents: String) -> Bool {
  string.contains(contents, "\"schema_version\"")
  && string.contains(contents, "\"sources\"")
  && string.contains(contents, "\"examples\"")
  && string.contains(contents, "\"ignored\"")
}

fn manifest_paths() -> List(String) {
  [
    "examples/upstream/minimal",
    "examples/upstream/hello_world",
    "examples/upstream/counter",
    "examples/upstream/counter_hold",
    "examples/upstream/complex_counter",
    "examples/upstream/shopping_list",
    "examples/upstream/todo_mvc",
    "examples/upstream/todo_mvc_physical",
    "examples/terminal/pong",
    "examples/terminal/arkanoid",
  ]
}

fn count_occurrences(contents: String, needle: String) -> Int {
  contents
  |> string.split(on: needle)
  |> list.length
  |> fn(parts) { parts - 1 }
}

fn codegen(path: String, args: List(String)) -> Nil {
  let target = flag_string(args, "--target", "core")
  case target {
    "web" -> web(path, ["--mode", "durable-client"])
    "core" | "terminal" | "backend" -> codegen_core(path, target)
    _ ->
      fail_with_diagnostics([
        diagnostic.error(
          code: "unsupported_codegen_target",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "unsupported codegen target: " <> target,
          help: "use --target core, terminal, backend, or web",
        ),
      ])
  }
}

fn codegen_core(path: String, target: String) -> Nil {
  case loader.load(path) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(project) ->
      case loader.parse_project(project) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(program) ->
          case pipeline.lower(project.name, project.entry_file.path, program) {
            Error(diagnostics) -> fail_with_diagnostics(diagnostics)
            Ok(flow) ->
              case core_codegen.write(path, flow) {
                Error(diagnostics) -> fail_with_diagnostics(diagnostics)
                Ok(output_path) ->
                  io.println("generated " <> target <> " " <> output_path)
              }
          }
      }
  }
}

fn verify(path: String, report_path: String) -> Nil {
  case runner.verify(path) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) -> {
      maybe_write_report(report_path, semantic_report_json(report))
      io.println(
        "verified "
        <> report.example
        <> ": expected text `"
        <> report.expected_text
        <> "`",
      )
    }
  }
}

fn maybe_write_report(path: String, contents: String) -> Nil {
  case string.trim(path) {
    "" -> Nil
    _ ->
      case file.write_text_file(path, contents) {
        Ok(_) -> Nil
        Error(message) ->
          fail_with_diagnostics([
            diagnostic.error(
              code: "report_write_failed",
              path: path,
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: message,
              help: "verify --report must be writable",
            ),
          ])
      }
  }
}

fn semantic_report_json(report: verify_report.VerifyReport) -> String {
  "{\n"
  <> "  \"example\": \""
  <> escape_json(report.example)
  <> "\",\n"
  <> "  \"passed\": "
  <> bool_json(report.passed)
  <> ",\n"
  <> "  \"actual_text\": \""
  <> escape_json(report.actual_text)
  <> "\",\n"
  <> "  \"expected_text\": \""
  <> escape_json(report.expected_text)
  <> "\"\n"
  <> "}\n"
}

fn terminal_report_json(report: terminal_smoke.SmokeReport) -> String {
  "{\n"
  <> "  \"example\": \""
  <> escape_json(report.example)
  <> "\",\n"
  <> "  \"ticks\": "
  <> int.to_string(report.ticks)
  <> ",\n"
  <> "  \"timeout_ms\": "
  <> int.to_string(report.timeout_ms)
  <> ",\n"
  <> "  \"score\": \""
  <> escape_json(report.score)
  <> "\",\n"
  <> "  \"hash\": \""
  <> escape_json(report.hash)
  <> "\"\n"
  <> "}\n"
}

fn bool_json(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

fn escape_json(value: String) -> String {
  value
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: "\"", with: "\\\"")
  |> string.replace(each: "\n", with: "\\n")
}

fn fail_with_diagnostics(diagnostics) -> Nil {
  list.each(diagnostics, fn(item) { io.println(diagnostic.to_line(item)) })
  os.exit(1)
}
