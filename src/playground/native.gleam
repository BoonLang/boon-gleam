import frontend/diagnostic.{type Diagnostic, error}
import gleam/erlang/charlist.{type Charlist}
import gleam/string
import playground/core
import support/file

@external(erlang, "os", "cmd")
fn os_cmd(command: Charlist) -> Charlist

pub type NativeDoctorReport {
  NativeDoctorReport(sdl3: String, bridge: String, dependency_mode: String)
}

pub fn doctor() -> NativeDoctorReport {
  let sdl3 = pkg_config_probe()
  let bridge = case file.is_directory(".boon-local/gui") {
    True -> "repo-local-gui-dir-present"
    False -> "missing-repo-local-gui-dir"
  }
  NativeDoctorReport(
    sdl3: sdl3,
    bridge: bridge,
    dependency_mode: "repo-local-preferred",
  )
}

pub fn doctor_json(report: NativeDoctorReport) -> String {
  "{\n"
  <> "  \"sdl3\": \""
  <> core.escape_json(report.sdl3)
  <> "\",\n"
  <> "  \"bridge\": \""
  <> core.escape_json(report.bridge)
  <> "\",\n"
  <> "  \"dependency_mode\": \""
  <> core.escape_json(report.dependency_mode)
  <> "\"\n"
  <> "}\n"
}

pub fn run(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  let doctor_report = doctor()
  case doctor_report.sdl3 {
    "available" -> verify(selector, report_path)
    _ -> {
      use scene <- result_try(core.scene(selector, core.NativeGuiTarget))
      let proof =
        core.PlaygroundProof(
          command: "gui",
          target: core.NativeGuiTarget,
          example: scene.example.name,
          status: "fail",
          runtime_origin: "generated-boon-gleam-core",
          scene_nonblank: True,
          semantic_ids_present: True,
          hit_regions_present: True,
          source_path: scene.source_path,
          failures: [
            "SDL3 native shell is unavailable: "
            <> doctor_report.sdl3
            <> "; "
            <> doctor_report.bridge,
          ],
        )
      use _ <- result_try_io(
        file.write_text_file(report_path, core.proof_json(proof)),
        report_path,
      )
      Error([
        error(
          code: "native_gui_unavailable",
          path: "gui",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "SDL3 native GUI shell is unavailable: "
            <> doctor_report.sdl3,
          help: "run `gleam run -m boongleam -- gui --bootstrap` after the SDL3 bridge is implemented, or inspect "
            <> report_path,
        ),
      ])
    }
  }
}

pub fn verify(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  use scene <- result_try(core.scene(selector, core.NativeGuiTarget))
  let proof = core.proof("verify-gui", scene)
  use _ <- result_try_io(
    file.write_text_file(report_path, core.proof_json(proof)),
    report_path,
  )
  Ok(proof)
}

pub fn bootstrap_report(path: String) -> Result(String, List(Diagnostic)) {
  let report =
    "{\n"
    <> "  \"status\": \"blocked\",\n"
    <> "  \"reason\": \"repo-local SDL3 bootstrap is specified but the native bridge has not been vendored yet\",\n"
    <> "  \"expected_dir\": \".boon-local/gui\"\n"
    <> "}\n"
  use _ <- result_try_io(file.write_text_file(path, report), path)
  Ok(report)
}

fn pkg_config_probe() -> String {
  let output =
    os_cmd(charlist.from_string(
      "sh -c 'pkg-config --exists sdl3 || pkg-config --exists SDL3; echo $?'",
    ))
    |> charlist.to_string
    |> string.trim
  case output {
    "0" -> "available"
    "127" -> "pkg-config-missing"
    _ -> "pkg-config-could-not-resolve-sdl3-or-SDL3"
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

fn result_try_io(
  result: Result(a, String),
  path: String,
  next: fn(a) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(message) ->
      Error([
        error(
          code: "native_playground_io_failed",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "native playground reports must be writable under build/reports",
        ),
      ])
  }
}
