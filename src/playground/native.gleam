import frontend/diagnostic.{type Diagnostic, error}
import gleam/erlang/charlist.{type Charlist}
import gleam/list
import gleam/string
import playground/core
import support/background_launch
import support/file

@external(erlang, "os", "cmd")
fn os_cmd(command: Charlist) -> Charlist

pub type NativeDoctorReport {
  NativeDoctorReport(
    sdl3: String,
    sdl3_package: String,
    sdl3_ttf: String,
    sdl3_binary: String,
    cosmic_background_launch: String,
    bridge: String,
    dependency_mode: String,
  )
}

pub fn doctor() -> NativeDoctorReport {
  let probe = sdl3_probe()
  let bridge = case file.is_file(sdl_source()) {
    True -> "repo-local-sdl3-shell-present"
    False -> "missing-repo-local-sdl3-shell"
  }
  NativeDoctorReport(
    sdl3: probe.status,
    sdl3_package: probe.package_name,
    sdl3_ttf: sdl3_ttf_status(),
    sdl3_binary: case file.is_file(sdl_binary()) {
      True -> "available"
      False -> "missing"
    },
    cosmic_background_launch: case background_launch.available() {
      True -> "available"
      False -> "missing"
    },
    bridge: bridge,
    dependency_mode: "sdl3-only-no-gtk-fallback",
  )
}

pub fn doctor_json(report: NativeDoctorReport) -> String {
  "{\n"
  <> "  \"sdl3\": \""
  <> core.escape_json(report.sdl3)
  <> "\",\n"
  <> "  \"sdl3_package\": \""
  <> core.escape_json(report.sdl3_package)
  <> "\",\n"
  <> "  \"sdl3_ttf\": \""
  <> core.escape_json(report.sdl3_ttf)
  <> "\",\n"
  <> "  \"sdl3_binary\": \""
  <> core.escape_json(report.sdl3_binary)
  <> "\",\n"
  <> "  \"cosmic_background_launch\": \""
  <> core.escape_json(report.cosmic_background_launch)
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
  run_sdl3_window(selector, report_path, False)
}

pub fn run_sdl3(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  run_sdl3_window(selector, report_path, False)
}

pub fn verify_sdl3(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  run_sdl3_window(selector, report_path, True)
}

pub fn verify(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  verify_scene(selector, report_path, "verify-gui-headless")
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

fn run_sdl3_window(
  selector: String,
  report_path: String,
  verify_mode: Bool,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  use scene <- result_try(core.scene(selector, core.NativeGuiTarget))
  use _ <- result_try(write_native_catalog_scenes())
  let scene_path =
    "build/playgrounds/native-" <> scene.example.name <> "/scene.json"
  use _ <- result_try_io(
    file.write_text_file(scene_path, core.scene_json(scene)),
    scene_path,
  )
  let compile_failure = compile_sdl3()
  let run_failure = case compile_failure {
    [] ->
      case verify_mode {
        True -> run_sdl3_verify(scene_path)
        False -> run_sdl3_manual(scene_path)
      }
    failures -> failures
  }
  let base_proof = core.proof("verify-gui-sdl3", scene)
  let failures = list.append(base_proof.failures, run_failure)
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
  Ok(proof)
}

fn write_native_catalog_scenes() -> Result(Nil, List(Diagnostic)) {
  write_native_catalog_scene_loop(core.catalog())
}

fn write_native_catalog_scene_loop(
  examples: List(core.CatalogExample),
) -> Result(Nil, List(Diagnostic)) {
  case examples {
    [] -> Ok(Nil)
    [example, ..rest] -> {
      use scene <- result_try(core.scene(example.name, core.NativeGuiTarget))
      let scene_path =
        "build/playgrounds/native-" <> scene.example.name <> "/scene.json"
      use _ <- result_try_io(
        file.write_text_file(scene_path, core.scene_json(scene)),
        scene_path,
      )
      write_native_catalog_scene_loop(rest)
    }
  }
}

pub fn bootstrap_report(path: String) -> Result(String, List(Diagnostic)) {
  let failures = compile_sdl3()
  let report =
    "{\n"
    <> "  \"status\": \""
    <> case failures {
      [] -> "pass"
      _ -> "fail"
    }
    <> "\",\n"
    <> "  \"native_backend\": \"sdl3\",\n"
    <> "  \"sdl3_binary\": \""
    <> sdl_binary()
    <> "\",\n"
    <> "  \"failures\": "
    <> string_list_json(failures)
    <> "\n"
    <> "}\n"
  use _ <- result_try_io(file.write_text_file(path, report), path)
  case failures {
    [] -> Ok(report)
    [failure, ..] ->
      Error([
        error(
          code: "native_sdl3_bootstrap_failed",
          path: "gui --bootstrap",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: failure,
          help: "inspect " <> path,
        ),
      ])
  }
}

fn compile_sdl3() -> List(String) {
  let probe = sdl3_probe()
  case probe.status {
    "available" -> {
      let command =
        "mkdir -p build/native && "
        <> sdl_env()
        <> " cc "
        <> sdl_source()
        <> " -o "
        <> sdl_binary()
        <> " $("
        <> sdl_env()
        <> " pkg-config --cflags --libs "
        <> probe.package_name
        <> " sdl3-ttf"
        <> ")"
      case command_succeeds(command) && file.is_file(sdl_binary()) {
        True -> []
        False -> ["SDL3 native playground failed to compile"]
      }
    }
    status -> [
      "SDL3 native shell is unavailable: "
      <> status
      <> "; install/provide pkg-config packages `sdl3` and `sdl3-ttf`",
    ]
  }
}

fn run_sdl3_verify(scene_path: String) -> List(String) {
  let command =
    sdl_env()
    <> " "
    <> sdl_binary()
    <> " "
    <> scene_path
    <> " --verify --exit-ms 600"
  case background_launch.run_and_wait("native-sdl3-smoke", command, 20) {
    True -> []
    False -> [
      "SDL3 native playground verification process failed through cosmic-background-launch",
    ]
  }
}

fn run_sdl3_manual(scene_path: String) -> List(String) {
  let _ =
    command_succeeds(
      "pgrep -f \"^build/native/boon_sdl3_playground \" | xargs -r kill",
    )
  let command =
    "cosmic-background-launch --workspace boon-gleam -- "
    <> "sh -c "
    <> shell_quote(sdl_env() <> " " <> sdl_binary() <> " " <> scene_path)
  case command_succeeds(command) {
    True -> []
    False -> ["SDL3 native playground process failed"]
  }
}

fn sdl_source() -> String {
  "native/boon_sdl3_playground.c"
}

fn sdl_binary() -> String {
  "build/native/boon_sdl3_playground"
}

fn local_sdl_pkgconfig() -> String {
  ".boon-local/sdl3/lib/pkgconfig"
}

fn local_sdl_lib() -> String {
  ".boon-local/sdl3/lib"
}

fn sdl_env() -> String {
  "PKG_CONFIG_PATH=$PWD/"
  <> local_sdl_pkgconfig()
  <> "${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH} LD_LIBRARY_PATH=$PWD/"
  <> local_sdl_lib()
  <> "${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}

type Sdl3Probe {
  Sdl3Probe(status: String, package_name: String)
}

fn sdl3_probe() -> Sdl3Probe {
  case pkg_config_available_with_env("sdl3") {
    True -> Sdl3Probe(status: "available", package_name: "sdl3")
    False ->
      case pkg_config_available_with_env("SDL3") {
        True -> Sdl3Probe(status: "available", package_name: "SDL3")
        False ->
          Sdl3Probe(
            status: "pkg-config-could-not-resolve-sdl3-or-SDL3",
            package_name: "",
          )
      }
  }
}

fn sdl3_ttf_status() -> String {
  case pkg_config_available_with_env("sdl3-ttf") {
    True -> "available"
    False -> "pkg-config-could-not-resolve-sdl3-ttf"
  }
}

fn pkg_config_available_with_env(name: String) -> Bool {
  os_cmd(charlist.from_string(
    "sh -c '" <> sdl_env() <> " pkg-config --exists " <> name <> "; echo $?'",
  ))
  |> charlist.to_string
  |> string.trim
  == "0"
}

fn command_succeeds(command: String) -> Bool {
  os_cmd(charlist.from_string(
    "sh -c " <> shell_quote(command <> "; echo EXIT:$?"),
  ))
  |> charlist.to_string
  |> string.contains("EXIT:0")
}

fn shell_quote(value: String) -> String {
  "'" <> string.replace(value, "'", "'\"'\"'") <> "'"
}

fn string_list_json(values: List(String)) -> String {
  "["
  <> {
    values
    |> list.map(fn(value) { "\"" <> core.escape_json(value) <> "\"" })
    |> string.join(with: ",")
  }
  <> "]"
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
          help: "native playground scene and report paths must be writable",
        ),
      ])
  }
}
