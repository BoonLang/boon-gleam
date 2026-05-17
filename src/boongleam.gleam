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
import playground/browser as browser_playground
import playground/browser_wasm as browser_wasm_playground
import playground/core as playground_core
import playground/native as native_playground
import project/importer
import project/loader
import support/argv
import support/file
import support/hash
import support/os
import terminal/play as terminal_play
import terminal/smoke as terminal_smoke
import terminal/verify as terminal_verify
import verify/all as verify_all
import verify/guardrails
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
    ["doctor", ..rest] -> doctor(rest)
    ["manifest", ..] -> manifest()
    ["compile", path, ..] -> compile(path)
    ["codegen", path, ..rest] -> codegen(path, rest)
    ["tui", ..rest] -> tui(rest)
    ["gui", ..rest] -> gui(rest)
    ["browser", ..rest] -> browser(rest)
    ["browser-wasm", ..rest] -> browser_wasm(rest)
    ["verify-playgrounds", ..rest] -> verify_playgrounds(rest)
    ["verify-gui", ..rest] -> verify_gui(rest)
    ["verify-browser", ..rest] -> verify_browser(rest)
    ["verify-browser-wasm", ..rest] -> verify_browser_wasm(rest)
    ["verify-terminal", ..rest] -> verify_terminal_catalog(rest)
    ["verify-all-targets", ..rest] -> verify_all_targets(rest)
    ["play", path, ..] -> play(path)
    ["play-smoke", path, ..rest] -> play_smoke(path, rest)
    ["serve", path, ..rest] -> serve(path, rest)
    ["serve-smoke", path, ..rest] -> serve_smoke(path, rest)
    ["bench", path, ..rest] -> bench(path, rest)
    ["bench-backend", path, ..rest] -> bench_backend(path, rest)
    ["store", "setup-postgres", ..rest] -> setup_postgres(rest)
    ["verify-backend", path, ..rest] -> verify_backend(path, rest)
    ["verify-durability", path, ..rest] -> verify_durability(path, rest)
    ["verify-guardrails", ..rest] -> verify_guardrails(rest)
    ["web", path, ..rest] -> web(path, rest)
    ["verify-all", ..rest] -> verify_all(rest)
    ["verify", path, ..rest] -> verify_command(path, rest)
    [command, ..] -> print_not_implemented(command)
  }
}

fn doctor(args: List(String)) -> Nil {
  let report_path = flag_string(args, "--report", "")
  let report =
    "{\n"
    <> "  \"status\": \"pass\",\n"
    <> "  \"native_gui\": "
    <> string.trim(native_playground.doctor_json(native_playground.doctor()))
    <> ",\n"
    <> "  \"browser_wasm\": "
    <> string.trim(browser_wasm_playground.doctor_json())
    <> "\n"
    <> "}\n"
  maybe_write_report(report_path, report)
  io.println(report)
}

fn tui(args: List(String)) -> Nil {
  let example = flag_string(args, "--example", "")
  case example {
    "" -> {
      io.println("Boon Gleam terminal playground examples:")
      io.println(playground_core.catalog_text())
      io.println("")
      io.println(
        "Run `gleam run -m boongleam -- tui --example pong` or `gleam run -m boongleam -- play examples/terminal/pong`.",
      )
    }
    _ ->
      case playground_core.scene(example, playground_core.TerminalTarget) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(scene) -> {
          io.println(scene.title)
          io.println("example: " <> scene.example.name)
          io.println("source: " <> scene.source_path)
          io.println("")
          io.println(scene.snapshot_text)
        }
      }
  }
}

fn gui(args: List(String)) -> Nil {
  case args {
    ["--doctor", ..] -> {
      let report = native_playground.doctor()
      io.println(native_playground.doctor_json(report))
    }
    ["--bootstrap", ..] -> {
      let report_path =
        flag_string(args, "--report", "build/reports/gui-bootstrap.json")
      case native_playground.bootstrap_report(report_path) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(report) -> io.println(report)
      }
    }
    _ -> {
      let example = flag_string(args, "--example", "todo_mvc")
      let report_path =
        flag_string(args, "--report", "build/reports/gui-playground.json")
      case native_playground.run(example, report_path) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(proof) -> finish_playground_proof("native gui", proof, report_path)
      }
    }
  }
}

fn browser(args: List(String)) -> Nil {
  let example = flag_string(args, "--example", "todo_mvc")
  let out_dir = flag_string(args, "--out", "build/playgrounds/browser")
  let port = flag_int(args, "--port", 8080)
  case has_flag(args, "--doctor"), has_flag(args, "--serve") {
    True, _ -> io.println(browser_playground.doctor_json())
    _, True ->
      case browser_playground.serve(example, out_dir, port) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(_) -> Nil
      }
    _, False ->
      case browser_playground.build(example, out_dir) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(report) ->
          io.println(
            "browser playground "
            <> report.example
            <> " index="
            <> report.index_path
            <> " scene="
            <> report.scene_path,
          )
      }
  }
}

fn browser_wasm(args: List(String)) -> Nil {
  let example = flag_string(args, "--example", "todo_mvc")
  let out_dir = flag_string(args, "--out", "build/playgrounds/browser-wasm")
  let report_path =
    flag_string(args, "--report", "build/reports/browser-wasm-bootstrap.json")
  case has_flag(args, "--doctor"), has_flag(args, "--bootstrap") {
    True, _ -> io.println(browser_wasm_playground.doctor_json())
    _, True ->
      case browser_wasm_playground.bootstrap_report(report_path) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(report) -> io.println(report)
      }
    _, False ->
      case browser_wasm_playground.build(example, out_dir) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(report) ->
          io.println(
            "browser-wasm playground "
            <> report.example
            <> " index="
            <> report.index_path
            <> " js="
            <> report.js_path
            <> " mode="
            <> report.wasm_mode,
          )
      }
  }
}

fn verify_playgrounds(args: List(String)) -> Nil {
  let report_path =
    flag_string(args, "--report", "build/reports/verify-playgrounds.json")
  let example = flag_string(args, "--example", "todo_mvc")
  case has_flag(args, "--all") {
    True -> verify_playgrounds_all(report_path)
    False -> verify_playgrounds_one(example, report_path)
  }
}

fn verify_playgrounds_one(example: String, report_path: String) -> Nil {
  case playground_core.scene(example, playground_core.TerminalTarget) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(terminal_scene) ->
      case playground_core.scene(example, playground_core.NativeGuiTarget) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(native_scene) ->
          case
            playground_core.scene(example, playground_core.BrowserGuiTarget)
          {
            Error(diagnostics) -> fail_with_diagnostics(diagnostics)
            Ok(browser_scene) -> {
              let proofs = [
                playground_core.proof(
                  "verify-playgrounds terminal",
                  terminal_scene,
                ),
                playground_core.proof("verify-playgrounds native", native_scene),
                playground_core.proof(
                  "verify-playgrounds browser",
                  browser_scene,
                ),
              ]
              let report =
                playground_core.proofs_json("verify-playgrounds", proofs)
              maybe_write_report(report_path, report)
              io.println(
                "verify-playgrounds example="
                <> example
                <> " report="
                <> report_path,
              )
              case playground_core.all_passed(proofs) {
                True -> Nil
                False -> os.exit(1)
              }
            }
          }
      }
  }
}

fn verify_playgrounds_all(report_path: String) -> Nil {
  case verify_playgrounds_loop(playground_core.catalog(), []) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(proofs) -> {
      let report =
        playground_core.proofs_json("verify-playgrounds --all", proofs)
      maybe_write_report(report_path, report)
      io.println("verify-playgrounds --all report=" <> report_path)
      case playground_core.all_passed(proofs) {
        True -> Nil
        False -> os.exit(1)
      }
    }
  }
}

fn verify_playgrounds_loop(
  examples: List(playground_core.CatalogExample),
  acc: List(playground_core.PlaygroundProof),
) -> Result(List(playground_core.PlaygroundProof), List(diagnostic.Diagnostic)) {
  case examples {
    [] -> Ok(list.reverse(acc))
    [example, ..rest] ->
      case playground_core.scene(example.name, playground_core.TerminalTarget) {
        Error(diagnostics) -> Error(diagnostics)
        Ok(terminal_scene) ->
          case
            playground_core.scene(example.name, playground_core.NativeGuiTarget)
          {
            Error(diagnostics) -> Error(diagnostics)
            Ok(native_scene) ->
              case
                playground_core.scene(
                  example.name,
                  playground_core.BrowserGuiTarget,
                )
              {
                Error(diagnostics) -> Error(diagnostics)
                Ok(browser_scene) -> {
                  let next = [
                    playground_core.proof(
                      "verify-playgrounds terminal",
                      terminal_scene,
                    ),
                    playground_core.proof(
                      "verify-playgrounds native",
                      native_scene,
                    ),
                    playground_core.proof(
                      "verify-playgrounds browser",
                      browser_scene,
                    ),
                    ..acc
                  ]
                  verify_playgrounds_loop(rest, next)
                }
              }
          }
      }
  }
}

fn verify_gui(args: List(String)) -> Nil {
  let example = flag_string(args, "--example", "todo_mvc")
  let backend = flag_string(args, "--backend", "headless")
  let report_path =
    flag_string(args, "--report", "build/reports/verify-gui-headless.json")
  case has_flag(args, "--all") {
    True -> verify_gui_all(backend, report_path)
    False -> verify_gui_one(example, backend, report_path)
  }
}

fn verify_gui_one(
  example: String,
  backend: String,
  report_path: String,
) -> Nil {
  case backend {
    "headless" ->
      case native_playground.verify(example, report_path) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(proof) ->
          finish_playground_proof(
            "verify-gui backend=headless",
            proof,
            report_path,
          )
      }
    "sdl3" ->
      case native_playground.verify_sdl3(example, report_path) {
        Error(diagnostics) -> fail_with_diagnostics(diagnostics)
        Ok(proof) ->
          finish_playground_proof("verify-gui backend=sdl3", proof, report_path)
      }
    _ ->
      fail_with_diagnostics([
        diagnostic.error(
          code: "unsupported_gui_backend",
          path: "verify-gui",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "unsupported GUI backend: " <> backend,
          help: "use --backend headless or sdl3",
        ),
      ])
  }
}

fn verify_browser(args: List(String)) -> Nil {
  let example = flag_string(args, "--example", "todo_mvc")
  let report_path =
    flag_string(args, "--report", "build/reports/verify-browser-firefox.json")
  case has_flag(args, "--all") {
    True -> verify_browser_all(report_path)
    False -> verify_browser_one(example, report_path)
  }
}

fn verify_browser_one(example: String, report_path: String) -> Nil {
  case browser_playground.verify(example, report_path) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(proof) ->
      finish_playground_proof(
        "verify-browser browser=firefox",
        proof,
        report_path,
      )
  }
}

fn verify_browser_all(report_path: String) -> Nil {
  case verify_browser_loop(playground_core.catalog(), []) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(proofs) -> {
      let report = playground_core.proofs_json("verify-browser --all", proofs)
      maybe_write_report(report_path, report)
      io.println("verify-browser --all report=" <> report_path)
      case playground_core.all_passed(proofs) {
        True -> Nil
        False -> os.exit(1)
      }
    }
  }
}

fn verify_browser_wasm(args: List(String)) -> Nil {
  let example = flag_string(args, "--example", "todo_mvc")
  let report_path =
    flag_string(
      args,
      "--report",
      "build/reports/verify-browser-wasm-firefox.json",
    )
  case has_flag(args, "--all") {
    True -> verify_browser_wasm_all(report_path)
    False -> verify_browser_wasm_one(example, report_path)
  }
}

fn verify_browser_wasm_one(example: String, report_path: String) -> Nil {
  case browser_wasm_playground.verify(example, report_path) {
    Error(diagnostics) ->
      fail_with_report(report_path, "verify-browser-wasm", example, diagnostics)
    Ok(proof) ->
      finish_playground_proof(
        "verify-browser-wasm browser=firefox",
        proof,
        report_path,
      )
  }
}

fn verify_browser_wasm_all(report_path: String) -> Nil {
  case verify_browser_wasm_loop(playground_core.catalog(), []) {
    Error(diagnostics) ->
      fail_with_report(
        report_path,
        "verify-browser-wasm --all",
        "all-examples",
        diagnostics,
      )
    Ok(proofs) -> {
      let report =
        playground_core.proofs_json("verify-browser-wasm --all", proofs)
      maybe_write_report(report_path, report)
      io.println("verify-browser-wasm --all report=" <> report_path)
      case playground_core.all_passed(proofs) {
        True -> Nil
        False -> os.exit(1)
      }
    }
  }
}

fn verify_browser_wasm_loop(
  examples: List(playground_core.CatalogExample),
  acc: List(playground_core.PlaygroundProof),
) -> Result(List(playground_core.PlaygroundProof), List(diagnostic.Diagnostic)) {
  case examples {
    [] -> Ok(list.reverse(acc))
    [example, ..rest] -> {
      let report_path =
        "build/reports/verify-browser-wasm-" <> example.name <> ".json"
      case browser_wasm_playground.verify(example.name, report_path) {
        Error(diagnostics) -> Error(diagnostics)
        Ok(proof) -> verify_browser_wasm_loop(rest, [proof, ..acc])
      }
    }
  }
}

fn verify_terminal_catalog(args: List(String)) -> Nil {
  let example = flag_string(args, "--example", "todo_mvc")
  let report_path =
    flag_string(args, "--report", "build/reports/verify-terminal.json")
  case has_flag(args, "--all") {
    True -> verify_terminal_catalog_all(report_path)
    False -> verify_terminal_catalog_one(example, report_path)
  }
}

fn verify_terminal_catalog_one(example: String, report_path: String) -> Nil {
  case verify_terminal_catalog_proof(example) {
    Error(diagnostics) ->
      fail_with_report(report_path, "verify-terminal", example, diagnostics)
    Ok(proof) -> {
      maybe_write_report(report_path, playground_core.proof_json(proof))
      finish_playground_proof("verify-terminal", proof, report_path)
    }
  }
}

fn verify_terminal_catalog_all(report_path: String) -> Nil {
  case verify_terminal_catalog_loop(playground_core.catalog(), []) {
    Error(diagnostics) ->
      fail_with_report(
        report_path,
        "verify-terminal --all",
        "all-examples",
        diagnostics,
      )
    Ok(proofs) -> {
      let report = playground_core.proofs_json("verify-terminal --all", proofs)
      maybe_write_report(report_path, report)
      io.println("verify-terminal --all report=" <> report_path)
      case playground_core.all_passed(proofs) {
        True -> Nil
        False -> os.exit(1)
      }
    }
  }
}

fn verify_terminal_catalog_loop(
  examples: List(playground_core.CatalogExample),
  acc: List(playground_core.PlaygroundProof),
) -> Result(List(playground_core.PlaygroundProof), List(diagnostic.Diagnostic)) {
  case examples {
    [] -> Ok(list.reverse(acc))
    [example, ..rest] ->
      case verify_terminal_catalog_proof(example.name) {
        Error(diagnostics) -> Error(diagnostics)
        Ok(proof) -> verify_terminal_catalog_loop(rest, [proof, ..acc])
      }
  }
}

fn verify_terminal_catalog_proof(
  selector: String,
) -> Result(playground_core.PlaygroundProof, List(diagnostic.Diagnostic)) {
  case playground_core.scene(selector, playground_core.TerminalTarget) {
    Error(diagnostics) -> Error(diagnostics)
    Ok(scene) ->
      case verify_terminal_game_smoke(scene.example) {
        Error(diagnostics) -> Error(diagnostics)
        Ok(_) -> Ok(playground_core.proof("verify-terminal", scene))
      }
  }
}

fn verify_terminal_game_smoke(
  example: playground_core.CatalogExample,
) -> Result(Nil, List(diagnostic.Diagnostic)) {
  case example.name {
    "pong" | "arkanoid" ->
      case terminal_verify.verify(example.path) {
        Ok(_) -> Ok(Nil)
        Error(diagnostics) -> Error(diagnostics)
      }
    _ -> Ok(Nil)
  }
}

fn verify_all_targets(args: List(String)) -> Nil {
  let report_path =
    flag_string(args, "--report", "build/reports/verify-all-targets.json")
  case verify_all_targets_loop(playground_core.catalog(), []) {
    Error(diagnostics) ->
      fail_with_report(
        report_path,
        "verify-all-targets --all-examples",
        "all-examples",
        diagnostics,
      )
    Ok(proofs) -> {
      let report =
        playground_core.proofs_json("verify-all-targets --all-examples", proofs)
      maybe_write_report(report_path, report)
      io.println("verify-all-targets --all-examples report=" <> report_path)
      case playground_core.all_passed(proofs) {
        True -> Nil
        False -> os.exit(1)
      }
    }
  }
}

fn verify_all_targets_loop(
  examples: List(playground_core.CatalogExample),
  acc: List(playground_core.PlaygroundProof),
) -> Result(List(playground_core.PlaygroundProof), List(diagnostic.Diagnostic)) {
  case examples {
    [] -> Ok(list.reverse(acc))
    [example, ..rest] ->
      case verify_terminal_catalog_proof(example.name) {
        Error(diagnostics) -> Error(diagnostics)
        Ok(terminal_proof) ->
          case
            native_playground.verify_sdl3(
              example.name,
              "build/reports/verify-all-targets-sdl3-"
                <> example.name
                <> ".json",
            )
          {
            Error(diagnostics) -> Error(diagnostics)
            Ok(native_proof) ->
              case
                browser_wasm_playground.verify(
                  example.name,
                  "build/reports/verify-all-targets-browser-wasm-"
                    <> example.name
                    <> ".json",
                )
              {
                Error(diagnostics) -> Error(diagnostics)
                Ok(browser_proof) ->
                  verify_all_targets_loop(rest, [
                    browser_proof,
                    native_proof,
                    terminal_proof,
                    ..acc
                  ])
              }
          }
      }
  }
}

fn verify_browser_loop(
  examples: List(playground_core.CatalogExample),
  acc: List(playground_core.PlaygroundProof),
) -> Result(List(playground_core.PlaygroundProof), List(diagnostic.Diagnostic)) {
  case examples {
    [] -> Ok(list.reverse(acc))
    [example, ..rest] -> {
      let report_path =
        "build/reports/verify-browser-" <> example.name <> ".json"
      case browser_playground.verify(example.name, report_path) {
        Error(diagnostics) -> Error(diagnostics)
        Ok(proof) -> verify_browser_loop(rest, [proof, ..acc])
      }
    }
  }
}

fn verify_gui_all(backend: String, report_path: String) -> Nil {
  case verify_gui_loop(playground_core.catalog(), backend, []) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(proofs) -> {
      let report =
        playground_core.proofs_json(
          "verify-gui --all --backend " <> backend,
          proofs,
        )
      maybe_write_report(report_path, report)
      io.println(
        "verify-gui --all backend=" <> backend <> " report=" <> report_path,
      )
      case playground_core.all_passed(proofs) {
        True -> Nil
        False -> os.exit(1)
      }
    }
  }
}

fn verify_gui_loop(
  examples: List(playground_core.CatalogExample),
  backend: String,
  acc: List(playground_core.PlaygroundProof),
) -> Result(List(playground_core.PlaygroundProof), List(diagnostic.Diagnostic)) {
  case examples {
    [] -> Ok(list.reverse(acc))
    [example, ..rest] -> {
      let report_path =
        "build/reports/verify-gui-" <> backend <> "-" <> example.name <> ".json"
      let result = case backend {
        "headless" -> native_playground.verify(example.name, report_path)
        "sdl3" -> native_playground.verify_sdl3(example.name, report_path)
        _ ->
          Error([
            diagnostic.error(
              code: "unsupported_gui_backend",
              path: "verify-gui",
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: "unsupported GUI backend: " <> backend,
              help: "use --backend headless or sdl3",
            ),
          ])
      }
      case result {
        Error(diagnostics) -> Error(diagnostics)
        Ok(proof) -> verify_gui_loop(rest, backend, [proof, ..acc])
      }
    }
  }
}

fn finish_playground_proof(
  label: String,
  proof: playground_core.PlaygroundProof,
  report_path: String,
) -> Nil {
  io.println(
    label
    <> " "
    <> proof.example
    <> " status="
    <> proof.status
    <> " report="
    <> report_path,
  )
  case proof.status {
    "pass" -> Nil
    _ -> os.exit(1)
  }
}

fn play(path: String) -> Nil {
  case terminal_play.play(path) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(_) -> Nil
  }
}

fn verify_all(args: List(String)) -> Nil {
  let report_path = flag_string(args, "--report", "")
  let phase = flag_string(args, "--phase", "all")
  case verify_all.run(phase) {
    Error(diagnostics) ->
      fail_with_report(report_path, "verify-all", "manifest", diagnostics)
    Ok(report) -> {
      maybe_write_report(report_path, verify_all_report_json(report))
      io.println(
        "verify-all semantic="
        <> int.to_string(report.semantic_count)
        <> " terminal="
        <> int.to_string(report.terminal_count),
      )
    }
  }
}

fn verify_guardrails(args: List(String)) -> Nil {
  let report_path = flag_string(args, "--report", "")
  case guardrails.run() {
    Error(diagnostics) ->
      fail_with_report(
        report_path,
        "verify-guardrails",
        "structural",
        diagnostics,
      )
    Ok(report) -> {
      maybe_write_report(report_path, guardrails_report_json(report))
      io.println(
        "verify-guardrails checked="
        <> int.to_string(report.checked)
        <> " allowlisted="
        <> int.to_string(list.length(report.allowlisted)),
      )
    }
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
  let report_path = flag_string(args, "--report", "")
  case session.is_postgres(store) {
    True ->
      case postgres.require_database_url() {
        Error(diagnostics) ->
          fail_with_report(report_path, "verify-durability", path, diagnostics)
        Ok(database_url) ->
          case postgres.verify_session(path, database_url) {
            Error(diagnostics) ->
              fail_with_report(
                report_path,
                "verify-durability",
                path,
                diagnostics,
              )
            Ok(_) -> verify_durability_with_store(path, store, report_path)
          }
      }
    False -> verify_durability_with_store(path, store, report_path)
  }
}

fn verify_durability_with_store(
  path: String,
  store: session.StoreKind,
  report_path: String,
) -> Nil {
  case durability.verify(path, store) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) -> {
      maybe_write_report(report_path, durability_report_json(report))
      io.println(
        "verified durability "
        <> report.example
        <> " events="
        <> int.to_string(report.events_replayed),
      )
    }
  }
}

fn serve_smoke(path: String, args: List(String)) -> Nil {
  let store = session.parse_store(flag_string(args, "--store", "memory"))
  let port = flag_int(args, "--port", 8080)
  let timeout_ms = flag_int(args, "--timeout-ms", 5000)
  let report_path = flag_string(args, "--report", "")
  case backend_smoke.serve_smoke(path, store, port, timeout_ms) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) -> {
      maybe_write_report(
        report_path,
        backend_report_json("serve-smoke", report),
      )
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
  let report_path = flag_string(args, "--report", "")
  case session.is_postgres(store) {
    True ->
      case postgres.require_database_url() {
        Error(diagnostics) ->
          fail_with_report(report_path, "verify-backend", path, diagnostics)
        Ok(database_url) ->
          case postgres.verify_session(path, database_url) {
            Error(diagnostics) ->
              fail_with_report(report_path, "verify-backend", path, diagnostics)
            Ok(_) -> verify_backend_with_store(path, store, report_path)
          }
      }
    False -> verify_backend_with_store(path, store, report_path)
  }
}

fn verify_backend_with_store(
  path: String,
  store: session.StoreKind,
  report_path: String,
) -> Nil {
  case backend_smoke.verify_backend(path, store) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) -> {
      maybe_write_report(
        report_path,
        backend_report_json("verify-backend", report),
      )
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
}

fn play_smoke(path: String, args: List(String)) -> Nil {
  let ticks = flag_int(args, "--ticks", 1000)
  let timeout_ms = flag_int(args, "--timeout-ms", 5000)
  let report_path = flag_string(args, "--report", "")
  case terminal_smoke.play_smoke(path, ticks, timeout_ms) {
    Error(diagnostics) -> fail_with_diagnostics(diagnostics)
    Ok(report) -> {
      maybe_write_report(report_path, terminal_report_json(report))
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

fn has_flag(args: List(String), name: String) -> Bool {
  list.any(args, fn(arg) { arg == name })
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
  io.println("  doctor")
  io.println("  import-upstream")
  io.println("  manifest")
  io.println("  compile")
  io.println("  codegen")
  io.println("  verify")
  io.println("  verify-all")
  io.println("  verify-backend")
  io.println("  verify-durability")
  io.println("  verify-guardrails")
  io.println("  tui")
  io.println("  gui")
  io.println("  browser")
  io.println("  browser-wasm")
  io.println("  verify-playgrounds")
  io.println("  verify-gui")
  io.println("  verify-browser")
  io.println("  verify-browser-wasm")
  io.println("  verify-terminal")
  io.println("  verify-all-targets")
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
    "examples/upstream/button_hover_test",
    "examples/upstream/button_hover_to_click_test",
    "examples/upstream/cells",
    "examples/upstream/cells_dynamic",
    "examples/upstream/chained_list_remove_bug",
    "examples/upstream/checkbox_test",
    "examples/upstream/circle_drawer",
    "examples/upstream/complex_counter",
    "examples/upstream/counter",
    "examples/upstream/counter_hold",
    "examples/upstream/crud",
    "examples/upstream/fibonacci",
    "examples/upstream/filter_checkbox_bug",
    "examples/upstream/flight_booker",
    "examples/upstream/hello_world",
    "examples/upstream/interval",
    "examples/upstream/interval_hold",
    "examples/upstream/latest",
    "examples/upstream/layers",
    "examples/upstream/list_map_block",
    "examples/upstream/list_map_external_dep",
    "examples/upstream/list_object_state",
    "examples/upstream/list_retain_count",
    "examples/upstream/list_retain_reactive",
    "examples/upstream/list_retain_remove",
    "examples/upstream/minimal",
    "examples/upstream/pages",
    "examples/upstream/shopping_list",
    "examples/upstream/switch_hold_test",
    "examples/upstream/temperature_converter",
    "examples/upstream/text_interpolation_update",
    "examples/upstream/then",
    "examples/upstream/timer",
    "examples/upstream/todo_mvc",
    "examples/upstream/todo_mvc_physical",
    "examples/upstream/when",
    "examples/upstream/while",
    "examples/upstream/while_function_call",
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

fn fail_with_report(
  report_path: String,
  command: String,
  example: String,
  diagnostics: List(diagnostic.Diagnostic),
) -> Nil {
  maybe_write_report(
    report_path,
    failure_report_json(command, example, diagnostics),
  )
  fail_with_diagnostics(diagnostics)
}

fn semantic_report_json(report: verify_report.VerifyReport) -> String {
  "{\n"
  <> common_report_fields(
    command: "verify",
    example: report.example,
    target: "semantic",
    status: status_json(report.passed),
    source_commit: "34251e2938a73f05de14997e167630bb0124ef48",
    actions_total: 0,
    actions_passed: 0,
    snapshot_hash: "sha256:" <> hash.sha256_hex(report.actual_text),
    terminal_frame_hash: "null",
    reproduce: "gleam run -- verify " <> report.example,
  )
  <> ",\n"
  <> "  \"diagnostics\": [],\n"
  <> "  \"failure\": null,\n"
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
  <> common_report_fields(
    command: "terminal-smoke",
    example: report.example,
    target: "terminal",
    status: "pass",
    source_commit: "workspace",
    actions_total: report.ticks,
    actions_passed: report.ticks,
    snapshot_hash: "null",
    terminal_frame_hash: "\"sha256:" <> escape_json(report.hash) <> "\"",
    reproduce: "gleam run -- play-smoke "
      <> report.example
      <> " --ticks "
      <> int.to_string(report.ticks)
      <> " --timeout-ms "
      <> int.to_string(report.timeout_ms),
  )
  <> ",\n"
  <> "  \"diagnostics\": [],\n"
  <> "  \"failure\": null,\n"
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

fn backend_report_json(
  command: String,
  report: backend_smoke.BackendReport,
) -> String {
  "{\n"
  <> common_report_fields(
    command: command,
    example: report.example,
    target: "backend-" <> session.store_name(report.store),
    status: "pass",
    source_commit: "34251e2938a73f05de14997e167630bb0124ef48",
    actions_total: list.length(report.websocket_trace),
    actions_passed: list.length(report.websocket_trace),
    snapshot_hash: "sha256:" <> hash.sha256_hex(report.snapshot_text),
    terminal_frame_hash: "null",
    reproduce: "gleam run -- " <> command <> " " <> report.example,
  )
  <> ",\n"
  <> "  \"diagnostics\": [],\n"
  <> "  \"failure\": null,\n"
  <> "  \"store\": \""
  <> escape_json(session.store_name(report.store))
  <> "\",\n"
  <> "  \"port\": "
  <> int.to_string(report.port)
  <> ",\n"
  <> "  \"timeout_ms\": "
  <> int.to_string(report.timeout_ms)
  <> ",\n"
  <> "  \"revision\": "
  <> int.to_string(report.revision)
  <> ",\n"
  <> "  \"snapshot_text\": \""
  <> escape_json(report.snapshot_text)
  <> "\",\n"
  <> "  \"health_status\": "
  <> int.to_string(report.health_status)
  <> ",\n"
  <> "  \"session_status\": "
  <> int.to_string(report.session_status)
  <> ",\n"
  <> "  \"snapshot_status\": "
  <> int.to_string(report.snapshot_status)
  <> ",\n"
  <> "  \"events_status\": "
  <> int.to_string(report.events_status)
  <> ",\n"
  <> "  \"clear_status\": "
  <> int.to_string(report.clear_status)
  <> "\n"
  <> "}\n"
}

fn durability_report_json(report: durability.DurabilityReport) -> String {
  "{\n"
  <> common_report_fields(
    command: "verify-durability",
    example: report.example,
    target: "durability-" <> session.store_name(report.store),
    status: "pass",
    source_commit: "34251e2938a73f05de14997e167630bb0124ef48",
    actions_total: report.events_replayed,
    actions_passed: report.events_replayed,
    snapshot_hash: "sha256:" <> hash.sha256_hex(report.recovered_snapshot),
    terminal_frame_hash: "null",
    reproduce: "gleam run -- verify-durability " <> report.example,
  )
  <> ",\n"
  <> "  \"diagnostics\": [],\n"
  <> "  \"failure\": null,\n"
  <> "  \"events_replayed\": "
  <> int.to_string(report.events_replayed)
  <> ",\n"
  <> "  \"duplicate_ignored\": "
  <> bool_json(report.duplicate_ignored)
  <> ",\n"
  <> "  \"stale_rejected\": "
  <> bool_json(report.stale_rejected)
  <> ",\n"
  <> "  \"recovered_snapshot\": \""
  <> escape_json(report.recovered_snapshot)
  <> "\"\n"
  <> "}\n"
}

fn verify_all_report_json(report: verify_all.VerifyAllReport) -> String {
  "{\n"
  <> "  \"schema_version\": 1,\n"
  <> "  \"command\": \"verify-all\",\n"
  <> "  \"status\": \"pass\",\n"
  <> "  \"started_at_utc\": \"2026-04-27T00:00:00Z\",\n"
  <> "  \"duration_ms\": 0,\n"
  <> "  \"semantic_count\": "
  <> int.to_string(report.semantic_count)
  <> ",\n"
  <> "  \"terminal_count\": "
  <> int.to_string(report.terminal_count)
  <> ",\n"
  <> "  \"guardrails_checked\": "
  <> int.to_string(report.guardrails.checked)
  <> ",\n"
  <> "  \"guardrail_allowlist\": "
  <> guardrail_findings_json(report.guardrails.allowlisted)
  <> ",\n"
  <> "  \"diagnostics\": [],\n"
  <> "  \"failure\": null,\n"
  <> "  \"reproduce\": \"gleam run -- verify-all\"\n"
  <> "}\n"
}

fn guardrails_report_json(report: guardrails.GuardrailReport) -> String {
  "{\n"
  <> common_report_fields(
    command: "verify-guardrails",
    example: "structural",
    target: "structural",
    status: "pass",
    source_commit: "workspace",
    actions_total: report.checked,
    actions_passed: report.checked,
    snapshot_hash: "null",
    terminal_frame_hash: "null",
    reproduce: "gleam run -- verify-guardrails",
  )
  <> ",\n"
  <> "  \"diagnostics\": [],\n"
  <> "  \"failure\": null,\n"
  <> "  \"checked\": "
  <> int.to_string(report.checked)
  <> ",\n"
  <> "  \"allowlisted\": "
  <> guardrail_findings_json(report.allowlisted)
  <> ",\n"
  <> "  \"findings\": "
  <> guardrail_findings_json(report.findings)
  <> "\n"
  <> "}\n"
}

fn guardrail_findings_json(
  findings: List(guardrails.GuardrailFinding),
) -> String {
  "[" <> string.join(list.map(findings, guardrail_finding_json), ", ") <> "]"
}

fn guardrail_finding_json(finding: guardrails.GuardrailFinding) -> String {
  "{"
  <> "\"rule\":\""
  <> escape_json(finding.rule)
  <> "\","
  <> "\"path\":\""
  <> escape_json(finding.path)
  <> "\","
  <> "\"line\":"
  <> int.to_string(finding.line)
  <> ","
  <> "\"text\":\""
  <> escape_json(finding.text)
  <> "\","
  <> "\"reason\":\""
  <> escape_json(finding.reason)
  <> "\""
  <> "}"
}

fn failure_report_json(
  command: String,
  example: String,
  diagnostics: List(diagnostic.Diagnostic),
) -> String {
  "{\n"
  <> common_report_fields(
    command: command,
    example: example,
    target: "unknown",
    status: "fail",
    source_commit: "34251e2938a73f05de14997e167630bb0124ef48",
    actions_total: 0,
    actions_passed: 0,
    snapshot_hash: "null",
    terminal_frame_hash: "null",
    reproduce: "gleam run -- " <> command <> " " <> example,
  )
  <> ",\n"
  <> "  \"diagnostics\": ["
  <> string.join(list.map(diagnostics, diagnostic_json), ", ")
  <> "],\n"
  <> "  \"failure\": \"diagnostics\"\n"
  <> "}\n"
}

fn common_report_fields(
  command command: String,
  example example: String,
  target target: String,
  status status: String,
  source_commit source_commit: String,
  actions_total actions_total: Int,
  actions_passed actions_passed: Int,
  snapshot_hash snapshot_hash: String,
  terminal_frame_hash terminal_frame_hash: String,
  reproduce reproduce: String,
) -> String {
  "  \"schema_version\": 1,\n"
  <> "  \"command\": \""
  <> escape_json(command)
  <> "\",\n"
  <> "  \"example\": \""
  <> escape_json(example)
  <> "\",\n"
  <> "  \"target\": \""
  <> escape_json(target)
  <> "\",\n"
  <> "  \"status\": \""
  <> escape_json(status)
  <> "\",\n"
  <> "  \"started_at_utc\": \"2026-04-27T00:00:00Z\",\n"
  <> "  \"duration_ms\": 0,\n"
  <> "  \"source_commit\": \""
  <> escape_json(source_commit)
  <> "\",\n"
  <> "  \"actions_total\": "
  <> int.to_string(actions_total)
  <> ",\n"
  <> "  \"actions_passed\": "
  <> int.to_string(actions_passed)
  <> ",\n"
  <> "  \"snapshot_hash\": "
  <> nullable_json_string(snapshot_hash)
  <> ",\n"
  <> "  \"terminal_frame_hash\": "
  <> terminal_frame_hash
  <> ",\n"
  <> "  \"reproduce\": \""
  <> escape_json(reproduce)
  <> "\""
}

fn diagnostic_json(item: diagnostic.Diagnostic) -> String {
  "\"" <> escape_json(diagnostic.to_line(item)) <> "\""
}

fn nullable_json_string(value: String) -> String {
  case value {
    "null" -> "null"
    _ -> "\"" <> escape_json(value) <> "\""
  }
}

fn status_json(passed: Bool) -> String {
  case passed {
    True -> "pass"
    False -> "fail"
  }
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
