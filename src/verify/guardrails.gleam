import frontend/diagnostic.{type Diagnostic, error}
import gleam/list
import gleam/string
import support/file

pub type GuardrailReport {
  GuardrailReport(
    checked: Int,
    allowlisted: List(GuardrailFinding),
    findings: List(GuardrailFinding),
  )
}

pub type GuardrailFinding {
  GuardrailFinding(
    rule: String,
    path: String,
    line: Int,
    text: String,
    reason: String,
  )
}

pub fn run() -> Result(GuardrailReport, List(Diagnostic)) {
  use generated_files <- result_try_io(list_files_or_empty("build/generated"))
  use verify_files <- result_try_io(list_files_or_empty("src/verify"))
  use terminal_files <- result_try_io(list_files_or_empty("src/terminal"))
  use playground_files <- result_try_io(list_files_or_empty("src/playground"))
  use source_files <- result_try_io(source_guardrail_files())

  let generated_app_files =
    generated_files
    |> list.filter(fn(path) { string.contains(path, "/src/generated_") })

  let generated_runtime =
    check_lines(
      generated_app_files,
      "generated_core_no_runtime_adapters",
      fn(path, line) { generated_runtime_violation(path, line) },
    )

  let generated_runtime_allowlist =
    check_lines(
      generated_app_files,
      "generated_core_no_runtime_adapters",
      fn(path, line) { allowlisted_timer_text(path, line) },
    )
    |> list.map(fn(finding) {
      GuardrailFinding(
        ..finding,
        reason: "generated timer fixture text contains the literal UI title; no runtime adapter is imported",
      )
    })

  let verifier_waits =
    check_lines(
      list.append(verify_files, terminal_files),
      "verifiers_no_wall_clock_waits",
      fn(_, line) {
        contains_any(line, [
          "sl" <> "eep",
          "set" <> "_timeout",
          "ti" <> "mer" <> "." <> "sl" <> "eep",
          "pro" <> "cess" <> "." <> "sl" <> "eep",
        ])
      },
    )

  let generated_maps =
    check_lines(
      generated_files,
      "generated_events_no_untyped_maps",
      fn(path, line) { untyped_map_violation(path, line) },
    )

  let generated_maps_allowlist =
    check_lines(
      generated_files,
      "generated_events_no_untyped_maps",
      fn(path, line) { allowlisted_lustre_dependency_map(path, line) },
    )
    |> list.map(fn(finding) {
      GuardrailFinding(
        ..finding,
        reason: "vendored Lustre dependency source under build/packages is outside generated Boon app code",
      )
    })

  let hidden_skips =
    check_lines(
      list.append(verify_files, source_files),
      "no_hidden_pass_skips",
      fn(_, line) { hidden_skip_violation(line) },
    )

  let source_names =
    check_lines(source_files, "no_source_name_special_casing", fn(_, line) {
      contains_any(line, ["counter", "todo_mvc", "pong", "arkanoid", "cells"])
    })

  let playground_names =
    check_lines(playground_files, "playground_catalog_name_review", fn(_, line) {
      contains_any(line, ["counter", "todo_mvc", "pong", "arkanoid", "cells"])
    })
    |> list.map(fn(finding) {
      GuardrailFinding(
        ..finding,
        reason: "playground catalog or report text references maintained example names; host code must not implement example behavior",
      )
    })

  let findings =
    [
      generated_runtime,
      verifier_waits,
      generated_maps,
      hidden_skips,
      source_names,
    ]
    |> list.flatten

  let allowlisted =
    [generated_runtime_allowlist, generated_maps_allowlist, playground_names]
    |> list.flatten

  let report =
    GuardrailReport(checked: 6, allowlisted: allowlisted, findings: findings)

  case findings {
    [] -> Ok(report)
    _ -> Error(list.map(findings, finding_diagnostic))
  }
}

fn source_guardrail_files() -> Result(List(String), String) {
  case list_files_or_empty("src/lowering") {
    Error(message) -> Error(message)
    Ok(lowering) ->
      case list_files_or_empty("src/runtime") {
        Error(message) -> Error(message)
        Ok(runtime) ->
          case list_files_or_empty("src/codegen") {
            Error(message) -> Error(message)
            Ok(codegen) ->
              Ok(list.append(list.append(lowering, runtime), codegen))
          }
      }
  }
}

fn list_files_or_empty(path: String) -> Result(List(String), String) {
  case file.is_directory(path) {
    False -> Ok([])
    True -> file.list_files_recursive(path)
  }
}

fn check_lines(
  paths: List(String),
  rule: String,
  predicate: fn(String, String) -> Bool,
) -> List(GuardrailFinding) {
  paths
  |> list.map(fn(path) { check_file(path, rule, predicate) })
  |> list.flatten
}

fn check_file(
  path: String,
  rule: String,
  predicate: fn(String, String) -> Bool,
) -> List(GuardrailFinding) {
  case file.read_text_file(path) {
    Error(_) -> []
    Ok(contents) ->
      contents
      |> string.split(on: "\n")
      |> list.index_map(fn(line, index) {
        case predicate(path, line) {
          True ->
            Ok(GuardrailFinding(
              rule: rule,
              path: path,
              line: index + 1,
              text: string.trim(line),
              reason: "",
            ))
          False -> Error(Nil)
        }
      })
      |> list.filter_map(fn(result) { result })
  }
}

fn generated_runtime_violation(path: String, line: String) -> Bool {
  contains_any(line, [
    "gleam_erlang",
    "gleam_otp",
    "mist",
    "shelf",
    "pog",
    "etch",
    "lustre",
    "File",
    "Process",
    "Timer",
  ])
  && !allowlisted_timer_text(path, line)
}

fn allowlisted_timer_text(path: String, line: String) -> Bool {
  string.contains(path, "build/generated/timer/src/generated_timer/view.gleam")
  && string.contains(line, "\"TimerElapsed Time:")
}

fn untyped_map_violation(path: String, line: String) -> Bool {
  contains_any(line, ["Dict(String", "Map(String"])
  && !string.contains(line, "event_json")
  && !allowlisted_lustre_dependency_map(path, line)
}

fn allowlisted_lustre_dependency_map(path: String, line: String) -> Bool {
  string.contains(path, "/build/packages/lustre/")
  && contains_any(line, ["Dict(String", "Map(String"])
}

fn hidden_skip_violation(line: String) -> Bool {
  string.contains(line, "fake " <> "pass")
  || string.contains(line, "hard" <> "code")
  || string.contains(line, "empty " <> "snapshot")
  || { string.contains(line, "TO" <> "DO") && string.contains(line, "pass") }
  || { string.contains(line, "sk" <> "ip") && string.contains(line, "example") }
}

fn contains_any(line: String, patterns: List(String)) -> Bool {
  list.any(patterns, fn(pattern) { string.contains(line, pattern) })
}

fn finding_diagnostic(finding: GuardrailFinding) -> Diagnostic {
  error(
    code: finding.rule,
    path: finding.path,
    line: finding.line,
    column: 1,
    span_start: 0,
    span_end: 0,
    message: "structural guardrail violation: " <> finding.text,
    help: "remove the violation or add a narrow allowlist reason if it is a legitimate false positive",
  )
}

fn result_try_io(
  result: Result(a, String),
  next: fn(a) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(message) ->
      Error([
        error(
          code: "guardrail_io_failed",
          path: "verify-guardrails",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "guardrail inputs must be readable",
        ),
      ])
  }
}
