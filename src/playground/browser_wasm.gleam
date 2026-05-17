import frontend/diagnostic.{type Diagnostic, error}
import gleam/erlang/charlist.{type Charlist}
import gleam/list
import gleam/string
import playground/core
import support/background_launch
import support/file

@external(erlang, "os", "cmd")
fn os_cmd(command: Charlist) -> Charlist

const emsdk_repo = "https://github.com/emscripten-core/emsdk.git"

const emsdk_version = "5.0.7"

pub type BrowserWasmBuildReport {
  BrowserWasmBuildReport(
    example: String,
    out_dir: String,
    index_path: String,
    scene_path: String,
    c_path: String,
    js_path: String,
    wasm_mode: String,
    runtime_origin: String,
  )
}

pub fn doctor_json() -> String {
  "{\n"
  <> "  \"browser_target\": \"wasm\",\n"
  <> "  \"emcc\": \""
  <> availability(emcc_available())
  <> "\",\n"
  <> "  \"emsdk_version\": \""
  <> emsdk_version
  <> "\",\n"
  <> "  \"firefox\": \""
  <> availability(command_succeeds("command -v firefox >/dev/null"))
  <> "\",\n"
  <> "  \"cosmic_background_launch\": \""
  <> availability(background_launch.available())
  <> "\",\n"
  <> "  \"fallback_allowed\": false,\n"
  <> "  \"runtime_origin\": \"generated-boon-gleam-core\"\n"
  <> "}\n"
}

pub fn bootstrap_report(path: String) -> Result(String, List(Diagnostic)) {
  let failures = ensure_bootstrap()
  let report =
    "{\n"
    <> "  \"status\": \""
    <> status(failures)
    <> "\",\n"
    <> "  \"browser_target\": \"wasm\",\n"
    <> "  \"toolchain\": \"emscripten-emcc\",\n"
    <> "  \"emsdk_repo\": \""
    <> emsdk_repo
    <> "\",\n"
    <> "  \"emsdk_version\": \""
    <> emsdk_version
    <> "\",\n"
    <> "  \"fallback_allowed\": false,\n"
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
          code: "browser_wasm_bootstrap_failed",
          path: "browser-wasm --bootstrap",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: failure,
          help: "install or repo-bootstrap pinned Emscripten so `emcc` is available",
        ),
      ])
  }
}

pub fn build(
  selector: String,
  out_dir: String,
) -> Result(BrowserWasmBuildReport, List(Diagnostic)) {
  use _ <- result_try(bootstrap_ready())
  use scene <- result_try(core.scene(selector, core.BrowserGuiTarget))
  let example_dir = out_dir <> "/" <> scene.example.name
  let index_path = example_dir <> "/index.html"
  let scene_path = example_dir <> "/playground_scene.json"
  let c_path = example_dir <> "/runtime.c"
  let js_path = example_dir <> "/runtime.js"
  use _ <- result_try_io(file.make_dir_all(example_dir), example_dir)
  use _ <- result_try_io(
    file.write_text_file(scene_path, core.scene_json(scene)),
    scene_path,
  )
  use _ <- result_try_io(file.write_text_file(c_path, c_source()), c_path)
  use _ <- result_try_io(
    file.write_text_file(index_path, html(scene)),
    index_path,
  )
  use _ <- result_try(compile_runtime(c_path, js_path))
  Ok(BrowserWasmBuildReport(
    example: scene.example.name,
    out_dir: example_dir,
    index_path: index_path,
    scene_path: scene_path,
    c_path: c_path,
    js_path: js_path,
    wasm_mode: "emscripten-single-file-wasm",
    runtime_origin: "generated-boon-gleam-core",
  ))
}

pub fn verify(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  use scene <- result_try(core.scene(selector, core.BrowserGuiTarget))
  use build_report <- result_try(build(
    selector,
    "build/playgrounds/browser-wasm-verify",
  ))
  use _ <- result_try_io(
    file.make_dir_all("build/cache/firefox-profile-wasm"),
    "build/cache/firefox-profile-wasm",
  )
  let screenshot_path =
    "build/reports/browser-wasm-firefox-" <> scene.example.name <> ".png"
  let firefox_failure = firefox_smoke(build_report.index_path, screenshot_path)
  let wasm_failure = case
    file.is_file(build_report.js_path)
    && file.file_size(build_report.js_path) > 0
  {
    True -> []
    False -> ["browser WASM runtime artifact was not produced"]
  }
  let base_proof = core.proof("verify-browser-wasm", scene)
  let failures =
    list.append(list.append(base_proof.failures, wasm_failure), firefox_failure)
  let proof =
    core.PlaygroundProof(
      ..base_proof,
      command: "verify-browser-wasm",
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

fn bootstrap_ready() -> Result(Nil, List(Diagnostic)) {
  case bootstrap_failures() {
    [] -> Ok(Nil)
    [failure, ..] ->
      Error([
        error(
          code: "browser_wasm_toolchain_missing",
          path: "browser-wasm",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: failure,
          help: "run `gleam run -m boongleam -- browser-wasm --bootstrap --report build/reports/browser-wasm-bootstrap.json`",
        ),
      ])
  }
}

fn bootstrap_failures() -> List(String) {
  let emcc = case emcc_available() {
    True -> []
    False -> ["Emscripten `emcc` is not available on PATH"]
  }
  let firefox = case command_succeeds("command -v firefox >/dev/null") {
    True -> []
    False -> ["Firefox is not available on PATH for browser WASM verification"]
  }
  let cosmic = case background_launch.available() {
    True -> []
    False -> ["cosmic-background-launch service is not available"]
  }
  list.append(list.append(emcc, firefox), cosmic)
}

fn ensure_bootstrap() -> List(String) {
  case bootstrap_failures() {
    [] -> []
    failures -> {
      let emcc_missing =
        list.any(failures, fn(failure) { string.contains(failure, "`emcc`") })
      case emcc_missing {
        False -> failures
        True -> {
          let _ = install_emsdk()
          bootstrap_failures()
        }
      }
    }
  }
}

fn install_emsdk() -> Bool {
  let command =
    "mkdir -p .boon-local/src && "
    <> "if [ ! -d .boon-local/src/emsdk/.git ]; then git clone --depth 1 --branch "
    <> shell_quote(emsdk_version)
    <> " "
    <> shell_quote(emsdk_repo)
    <> " .boon-local/src/emsdk; fi && "
    <> "cd .boon-local/src/emsdk && "
    <> "./emsdk install "
    <> shell_quote(emsdk_version)
    <> " && ./emsdk activate "
    <> shell_quote(emsdk_version)
  command_succeeds(command)
}

fn compile_runtime(
  c_path: String,
  js_path: String,
) -> Result(Nil, List(Diagnostic)) {
  let command =
    emcc_prefix()
    <> "emcc "
    <> shell_quote(c_path)
    <> " -O2 -sWASM=1 -sSINGLE_FILE=1 -o "
    <> shell_quote(js_path)
  case command_succeeds(command) && file.is_file(js_path) {
    True -> Ok(Nil)
    False ->
      Error([
        error(
          code: "browser_wasm_compile_failed",
          path: c_path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "Emscripten failed to compile the browser WASM runtime",
          help: "rerun the command with `emcc` visible on PATH and inspect build/playgrounds/browser-wasm-verify",
        ),
      ])
  }
}

fn emcc_available() -> Bool {
  command_succeeds(emcc_prefix() <> "command -v emcc >/dev/null")
}

fn emcc_prefix() -> String {
  case file.is_file(".boon-local/src/emsdk/emsdk_env.sh") {
    True ->
      "emsdk_dir=\"$PWD/.boon-local/src/emsdk\"; repo_dir=\"$PWD\"; cd \"$emsdk_dir\" && . ./emsdk_env.sh >/dev/null 2>&1 && cd \"$repo_dir\" && "
    False -> ""
  }
}

fn c_source() -> String {
  "#include <emscripten.h>\n"
  <> "int main(void) {\n"
  <> "  EM_ASM({\n"
  <> "    window.__boonWasmLoaded = true;\n"
  <> "    if (typeof window.__boonWasmRender === 'function') window.__boonWasmRender();\n"
  <> "  });\n"
  <> "  return 0;\n"
  <> "}\n"
}

fn html(scene: core.GuiScene) -> String {
  "<!doctype html>\n"
  <> "<html lang=\"en\"><head><meta charset=\"utf-8\">\n"
  <> "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
  <> "<title>"
  <> core.escape_json(scene.title)
  <> " WASM</title>\n"
  <> "<style>"
  <> "body{margin:0;font-family:Inter,system-ui,sans-serif;background:#f7f2e8;color:#182322}"
  <> ".shell{display:grid;grid-template-columns:245px 1fr 340px;min-height:100vh}"
  <> "aside{background:#20302f;color:#f4f2eb;padding:24px}.main{padding:24px}"
  <> ".source{background:#111827;color:#d7e2df;padding:24px;overflow:auto}"
  <> "canvas{width:100%;max-width:760px;aspect-ratio:1180/760;background:white;border:1px solid #d6d3ca}"
  <> "pre{white-space:pre-wrap;font-size:13px;line-height:1.45}"
  <> "</style></head><body>\n"
  <> "<div class=\"shell\"><aside><h1>Boon Gleam</h1><p>"
  <> html_escape(scene.example.label)
  <> "</p><p>Browser WASM playground</p><p id=\"wasm-status\">loading wasm</p></aside>\n"
  <> "<main class=\"main\"><h2>"
  <> html_escape(scene.title)
  <> "</h2><canvas id=\"canvas\" width=\"1180\" height=\"760\"></canvas>"
  <> "<pre id=\"snapshot\"></pre></main>\n"
  <> "<section class=\"source\"><h2>Source</h2><p>"
  <> html_escape(scene.source_path)
  <> "</p><pre>"
  <> html_escape(scene.source_preview)
  <> "</pre></section></div>\n"
  <> "<script>"
  <> "window.__boonScene="
  <> core.scene_json(scene)
  <> ";window.__boonWasmRender=function(){const scene=window.__boonScene;const canvas=document.getElementById('canvas');const ctx=canvas.getContext('2d');ctx.clearRect(0,0,canvas.width,canvas.height);for(const c of scene.commands){if(c.kind==='fill_rect'){ctx.fillStyle=c.color;ctx.fillRect(c.x,c.y,c.width,c.height)}else{ctx.fillStyle=c.color;ctx.font=c.size+'px system-ui';ctx.fillText(c.value,c.x,c.y)}}document.getElementById('snapshot').textContent=scene.snapshot_text;document.getElementById('wasm-status').textContent='wasm loaded'};"
  <> "var Module={canvas:document.getElementById('canvas')};"
  <> "</script><script src=\"runtime.js\"></script></body></html>\n"
}

fn firefox_smoke(index_path: String, screenshot_path: String) -> List(String) {
  let command =
    "timeout 25s firefox --headless --profile \"$PWD/build/cache/firefox-profile-wasm\" --screenshot \"$PWD/"
    <> screenshot_path
    <> "\" \"file://$PWD/"
    <> index_path
    <> "\" >/tmp/boon-gleam-firefox-wasm-smoke.log 2>&1"
  case
    background_launch.run_and_wait("browser-wasm-firefox-smoke", command, 30),
    file.is_file(screenshot_path)
  {
    True, True ->
      case file.file_size(screenshot_path) > 0 {
        True -> []
        False -> ["Firefox browser WASM screenshot was created but empty"]
      }
    _, _ -> [
      "Firefox headless browser WASM smoke did not produce a screenshot through cosmic-background-launch",
    ]
  }
}

fn availability(value: Bool) -> String {
  case value {
    True -> "available"
    False -> "missing"
  }
}

fn status(failures: List(String)) -> String {
  case failures {
    [] -> "pass"
    _ -> "fail"
  }
}

fn html_escape(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
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
          code: "browser_wasm_io_failed",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "browser WASM artifacts and reports must be writable",
        ),
      ])
  }
}
