import frontend/diagnostic.{type Diagnostic, error}
import gleam/erlang/charlist.{type Charlist}
import gleam/string
import playground/core
import support/background_launch
import support/file

@external(erlang, "os", "cmd")
fn os_cmd(command: Charlist) -> Charlist

pub type NativeDoctorReport {
  NativeDoctorReport(
    gtk4: String,
    gtk4_binary: String,
    cosmic_background_launch: String,
    sdl3: String,
    bridge: String,
    dependency_mode: String,
  )
}

pub fn doctor() -> NativeDoctorReport {
  let sdl3 = pkg_config_probe()
  let gtk4 = pkg_config_named("gtk4")
  let bridge = case file.is_directory(".boon-local/gui") {
    True -> "repo-local-gui-dir-present"
    False -> "missing-repo-local-gui-dir"
  }
  NativeDoctorReport(
    gtk4: gtk4,
    gtk4_binary: case file.is_file(gtk_binary()) {
      True -> "available"
      False -> "missing"
    },
    cosmic_background_launch: case background_launch.available() {
      True -> "available"
      False -> "missing"
    },
    sdl3: sdl3,
    bridge: bridge,
    dependency_mode: "gtk4-system-first-sdl3-repo-local-preferred",
  )
}

pub fn doctor_json(report: NativeDoctorReport) -> String {
  "{\n"
  <> "  \"gtk4\": \""
  <> core.escape_json(report.gtk4)
  <> "\",\n"
  <> "  \"gtk4_binary\": \""
  <> core.escape_json(report.gtk4_binary)
  <> "\",\n"
  <> "  \"cosmic_background_launch\": \""
  <> core.escape_json(report.cosmic_background_launch)
  <> "\",\n"
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
  run_gtk(selector, report_path, False)
}

pub fn run_sdl3(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  let doctor_report = doctor()
  case doctor_report.sdl3 {
    "available" -> verify_scene(selector, report_path, "verify-gui-sdl3")
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
      Ok(proof)
    }
  }
}

pub fn verify(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  verify_scene(selector, report_path, "verify-gui-headless")
}

pub fn verify_gtk(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  run_gtk(selector, report_path, True)
}

fn verify_scene(
  selector: String,
  report_path: String,
  command: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  use scene <- result_try(core.scene(selector, core.NativeGuiTarget))
  let proof = core.proof(command, scene)
  use _ <- result_try_io(
    file.write_text_file(report_path, core.proof_json(proof)),
    report_path,
  )
  Ok(proof)
}

fn run_gtk(
  selector: String,
  report_path: String,
  verify_mode: Bool,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  use scene <- result_try(core.scene(selector, core.NativeGuiTarget))
  let scene_path =
    "build/playgrounds/native-" <> scene.example.name <> "/scene.json"
  use _ <- result_try_io(
    file.write_text_file(scene_path, core.scene_json(scene)),
    scene_path,
  )
  let compile_failure = compile_gtk()
  let run_failure = case compile_failure {
    [] ->
      case verify_mode {
        True -> run_gtk_verify(scene_path)
        False -> run_gtk_manual(scene_path)
      }
    failures -> failures
  }
  let base_proof = core.proof("verify-gui-gtk4", scene)
  let failures = append_failures(base_proof.failures, run_failure)
  let proof =
    core.PlaygroundProof(
      ..base_proof,
      status: case failures {
        [] -> "pass"
        _ -> "fail"
      },
      failures: failures,
    )
  use _ <- result_try_io(
    file.write_text_file(report_path, core.proof_json(proof)),
    report_path,
  )
  case failures {
    [] -> Ok(proof)
    [failure, ..] ->
      Error([
        error(
          code: "native_gtk4_playground_failed",
          path: "gui",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: failure,
          help: "inspect " <> report_path,
        ),
      ])
  }
}

pub fn bootstrap_report(path: String) -> Result(String, List(Diagnostic)) {
  let failures = compile_gtk()
  let report =
    "{\n"
    <> "  \"status\": \""
    <> case failures {
      [] -> "pass"
      _ -> "fail"
    }
    <> "\",\n"
    <> "  \"gtk4_binary\": \""
    <> gtk_binary()
    <> "\",\n"
    <> "  \"sdl3_status\": \"not bootstrapped; gtk4 is the active native backend\"\n"
    <> "}\n"
  use _ <- result_try_io(file.write_text_file(path, report), path)
  Ok(report)
}

fn compile_gtk() -> List(String) {
  case pkg_config_named("gtk4") {
    "available" -> {
      let command =
        "mkdir -p build/native && cc native/boon_gtk_playground.c -o "
        <> gtk_binary()
        <> " $(pkg-config --cflags --libs gtk4)"
      case command_succeeds(command) && file.is_file(gtk_binary()) {
        True -> []
        False -> ["GTK4 native playground failed to compile"]
      }
    }
    status -> ["GTK4 is unavailable: " <> status]
  }
}

fn run_gtk_verify(scene_path: String) -> List(String) {
  let command = gtk_binary() <> " " <> scene_path <> " --verify --exit-ms 600"
  case background_launch.run_and_wait("native-gtk4-smoke", command, 20) {
    True -> []
    False -> [
      "GTK4 native playground verification process failed through cosmic-background-launch",
    ]
  }
}

fn run_gtk_manual(scene_path: String) -> List(String) {
  let command =
    "cosmic-background-launch --workspace boon-gleam -- "
    <> gtk_binary()
    <> " "
    <> scene_path
  case command_succeeds(command) {
    True -> []
    False -> ["GTK4 native playground process failed"]
  }
}

fn gtk_binary() -> String {
  "build/native/boon_gtk_playground"
}

fn pkg_config_probe() -> String {
  case pkg_config_named("sdl3") {
    "available" -> "available"
    _ -> pkg_config_named("SDL3")
  }
}

fn pkg_config_named(name: String) -> String {
  let output =
    os_cmd(charlist.from_string(
      "sh -c 'pkg-config --exists " <> name <> "; echo $?'",
    ))
    |> charlist.to_string
    |> string.trim
  case output {
    "0" -> "available"
    "127" -> "pkg-config-missing"
    _ -> "pkg-config-could-not-resolve-sdl3-or-SDL3"
  }
}

fn command_succeeds(command: String) -> Bool {
  os_cmd(charlist.from_string("sh -c '" <> command <> "; echo EXIT:$?'"))
  |> charlist.to_string
  |> string.contains("EXIT:0")
}

fn append_failures(left: List(String), right: List(String)) -> List(String) {
  case right {
    [] -> left
    _ -> list_append(left, right)
  }
}

fn list_append(left: List(String), right: List(String)) -> List(String) {
  case left {
    [] -> right
    [first, ..rest] -> [first, ..list_append(rest, right)]
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
