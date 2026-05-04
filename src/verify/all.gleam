import frontend/diagnostic.{type Diagnostic, error}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import support/file
import terminal/verify as terminal_verify
import verify/guardrails
import verify/runner

pub type VerifyAllReport {
  VerifyAllReport(
    semantic_count: Int,
    terminal_count: Int,
    guardrails: guardrails.GuardrailReport,
  )
}

pub type ManifestExample {
  ManifestExample(
    local_path: String,
    targets: List(String),
    phase: String,
    ignored: Bool,
  )
}

pub fn run(phase_filter: String) -> Result(VerifyAllReport, List(Diagnostic)) {
  use examples <- result_try(load_manifest_examples())

  let selected =
    examples
    |> list.filter(fn(example) {
      !example.ignored && phase_allowed(example.phase, phase_filter)
    })

  let semantic_examples =
    selected
    |> list.filter(fn(example) { list.contains(example.targets, "semantic") })
    |> list.map(fn(example) { example.local_path })

  let terminal_examples =
    selected
    |> list.filter(fn(example) { list.contains(example.targets, "terminal") })
    |> list.map(fn(example) { example.local_path })

  use _semantic <- result_try(list.try_map(semantic_examples, runner.verify))
  use _terminal <- result_try(list.try_map(
    terminal_examples,
    terminal_verify.verify,
  ))
  use guardrail_report <- result_try(guardrails.run())

  Ok(VerifyAllReport(
    semantic_count: list.length(semantic_examples),
    terminal_count: list.length(terminal_examples),
    guardrails: guardrail_report,
  ))
}

fn load_manifest_examples() -> Result(List(ManifestExample), List(Diagnostic)) {
  let manifest_path = "fixtures/corpus_manifest.json"
  case file.read_text_file(manifest_path) {
    Error(message) ->
      Error([
        loader_error(
          manifest_path,
          "manifest_read_failed",
          message,
          "fixtures/corpus_manifest.json is required before verify-all can select examples",
        ),
      ])
    Ok(contents) ->
      case json.parse(contents, manifest_decoder()) {
        Ok(examples) -> Ok(examples)
        Error(_) ->
          Error([
            loader_error(
              manifest_path,
              "manifest_decode_failed",
              "corpus manifest does not match the verify-all selection schema",
              "regenerate the corpus manifest with import-upstream",
            ),
          ])
      }
  }
}

fn manifest_decoder() -> decode.Decoder(List(ManifestExample)) {
  use examples <- decode.field("examples", decode.list(of: example_decoder()))
  decode.success(examples)
}

fn example_decoder() -> decode.Decoder(ManifestExample) {
  use local_path <- decode.field("local_path", decode.string)
  use targets <- decode.field("targets", decode.list(of: decode.string))
  use phase <- decode.field("phase", decode.string)
  use ignored <- decode.field("ignored", decode.bool)
  decode.success(ManifestExample(local_path, targets, phase, ignored))
}

fn phase_allowed(example_phase: String, phase_filter: String) -> Bool {
  let filter = case string.trim(phase_filter) {
    "" -> "all"
    phase -> phase
  }
  case filter {
    "all" -> True
    _ -> phase_rank(example_phase) <= phase_rank(filter)
  }
}

fn phase_rank(phase: String) -> Int {
  case phase {
    "frontend" -> 1
    "events" -> 3
    "terminal" -> 4
    "forms" -> 5
    "games" -> 8
    "build" -> 11
    "expanded" -> 12
    _ -> 99
  }
}

fn loader_error(
  path: String,
  code: String,
  message: String,
  help: String,
) -> Diagnostic {
  frontend_error(
    code: code,
    path: path,
    line: 1,
    column: 1,
    span_start: 0,
    span_end: 0,
    message: message,
    help: help,
  )
}

fn frontend_error(
  code code: String,
  path path: String,
  line line: Int,
  column column: Int,
  span_start span_start: Int,
  span_end span_end: Int,
  message message: String,
  help help: String,
) -> Diagnostic {
  error(
    code: code,
    path: path,
    line: line,
    column: column,
    span_start: span_start,
    span_end: span_end,
    message: message,
    help: help,
  )
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
