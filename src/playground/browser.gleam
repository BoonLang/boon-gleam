import frontend/diagnostic.{type Diagnostic, error}
import gleam/bytes_tree
import gleam/erlang/charlist.{type Charlist}
import gleam/erlang/process
import gleam/http.{Get}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import mist.{type Connection, type ResponseData}
import playground/core
import support/background_launch
import support/file

@external(erlang, "os", "cmd")
fn os_cmd(command: Charlist) -> Charlist

pub type BrowserBuildReport {
  BrowserBuildReport(
    example: String,
    out_dir: String,
    index_path: String,
    scene_path: String,
    runtime_origin: String,
  )
}

pub fn doctor_json() -> String {
  let firefox = case command_succeeds("command -v firefox >/dev/null") {
    True -> "available"
    False -> "missing"
  }
  let cosmic = case background_launch.available() {
    True -> "available"
    False -> "missing"
  }
  "{\n"
  <> "  \"browser\": \"firefox\",\n"
  <> "  \"firefox\": \""
  <> firefox
  <> "\",\n"
  <> "  \"cosmic_background_launch\": \""
  <> cosmic
  <> "\",\n"
  <> "  \"renderer\": \"canvas2d\",\n"
  <> "  \"runtime_origin\": \"generated-boon-gleam-core\"\n"
  <> "}\n"
}

pub fn build(
  selector: String,
  out_dir: String,
) -> Result(BrowserBuildReport, List(Diagnostic)) {
  use scene <- result_try(core.scene(selector, core.BrowserGuiTarget))
  let index_path = out_dir <> "/index.html"
  let scene_path = out_dir <> "/playground_scene.json"
  use _ <- result_try_io(file.make_dir_all(out_dir), index_path)
  use _ <- result_try_io(
    file.write_text_file(scene_path, core.scene_json(scene)),
    scene_path,
  )
  use _ <- result_try_io(
    file.write_text_file(index_path, html(scene)),
    index_path,
  )
  Ok(BrowserBuildReport(
    example: scene.example.name,
    out_dir: out_dir,
    index_path: index_path,
    scene_path: scene_path,
    runtime_origin: "generated-boon-gleam-core",
  ))
}

pub fn verify(
  selector: String,
  report_path: String,
) -> Result(core.PlaygroundProof, List(Diagnostic)) {
  use scene <- result_try(core.scene(selector, core.BrowserGuiTarget))
  use _ <- result_try(build(selector, "build/playgrounds/browser-verify"))
  use _ <- result_try_io(
    file.make_dir_all("build/cache/firefox-profile"),
    "build/cache/firefox-profile",
  )
  let screenshot_path =
    "build/reports/browser-firefox-" <> scene.example.name <> ".png"
  let firefox_failure = firefox_smoke(screenshot_path)
  let base_proof = core.proof("verify-browser", scene)
  let failures = list_append(base_proof.failures, firefox_failure)
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

pub fn serve(
  selector: String,
  out_dir: String,
  port: Int,
) -> Result(Nil, List(Diagnostic)) {
  use report <- result_try(build(selector, out_dir))
  let actual_port = case port {
    0 -> 8080
    _ -> port
  }
  let handler = fn(request) { handle_request(report.out_dir, request) }
  use _server <- result_try_server(
    handler
    |> mist.new
    |> mist.bind("127.0.0.1")
    |> mist.port(actual_port)
    |> mist.after_start(fn(_, _, _) { Nil })
    |> mist.start,
  )
  io.println(
    "browser playground serving http://127.0.0.1:"
    <> int.to_string(actual_port)
    <> "/",
  )
  process.sleep_forever()
  Ok(Nil)
}

fn handle_request(
  out_dir: String,
  request: Request(Connection),
) -> Response(ResponseData) {
  case request.method, request.path_segments(request) {
    Get, [] -> html_response(read_or_empty(out_dir <> "/index.html"))
    Get, ["index.html"] ->
      html_response(read_or_empty(out_dir <> "/index.html"))
    Get, ["playground_scene.json"] ->
      json_response(200, read_or_empty(out_dir <> "/playground_scene.json"))
    Get, ["health"] -> json_response(200, "{\"status\":\"ok\"}")
    _, _ -> json_response(404, "{\"error\":\"not_found\"}")
  }
}

fn read_or_empty(path: String) -> String {
  case file.read_text_file(path) {
    Ok(contents) -> contents
    Error(_) -> ""
  }
}

fn html(scene: core.GuiScene) -> String {
  "<!doctype html>\n"
  <> "<html lang=\"en\"><head><meta charset=\"utf-8\">\n"
  <> "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
  <> "<title>"
  <> core.escape_json(scene.title)
  <> "</title>\n"
  <> "<style>"
  <> "body{margin:0;font-family:Inter,system-ui,sans-serif;background:#f7f2e8;color:#182322}"
  <> ".shell{display:grid;grid-template-columns:245px 1fr 340px;min-height:100vh}"
  <> "aside{background:#20302f;color:#f4f2eb;padding:24px}.main{padding:24px}"
  <> ".source{background:#111827;color:#d7e2df;padding:24px;overflow:auto}"
  <> "canvas{width:100%;max-width:760px;aspect-ratio:1180/760;background:white;border:1px solid #d6d3ca}"
  <> "button{border:0;background:#d84f2a;color:white;padding:10px 14px;margin-right:8px}"
  <> "pre{white-space:pre-wrap;font-size:13px;line-height:1.45}"
  <> "</style></head><body>\n"
  <> "<div class=\"shell\"><aside><h1>Boon Gleam</h1><p>"
  <> scene.example.label
  <> "</p><p>Browser GUI playground</p></aside>\n"
  <> "<main class=\"main\"><h2>"
  <> scene.title
  <> "</h2><canvas id=\"scene\" width=\"1180\" height=\"760\"></canvas>"
  <> "<p><button id=\"rerun\">Run</button><button id=\"clear\">Clear state</button></p>"
  <> "<pre id=\"snapshot\"></pre></main>\n"
  <> "<section class=\"source\"><h2>Source</h2><p>"
  <> scene.source_path
  <> "</p><pre>"
  <> html_escape(scene.source_preview)
  <> "</pre></section></div>\n"
  <> "<script>"
  <> "const scene="
  <> core.scene_json(scene)
  <> ";const canvas=document.getElementById('scene');const ctx=canvas.getContext('2d');"
  <> "function draw(){ctx.clearRect(0,0,canvas.width,canvas.height);for(const c of scene.commands){if(c.kind==='fill_rect'){ctx.fillStyle=c.color;ctx.fillRect(c.x,c.y,c.width,c.height)}else{ctx.fillStyle=c.color;ctx.font=c.size+'px system-ui';ctx.fillText(c.value,c.x,c.y)}}document.getElementById('snapshot').textContent=scene.snapshot_text}"
  <> "canvas.addEventListener('click',e=>{const r=canvas.getBoundingClientRect();const x=(e.clientX-r.left)*canvas.width/r.width;const y=(e.clientY-r.top)*canvas.height/r.height;const hit=scene.hit_regions.find(h=>x>=h.x&&x<=h.x+h.width&&y>=h.y&&y<=h.y+h.height);if(hit){document.getElementById('snapshot').textContent=scene.snapshot_text+'\\ninput: '+hit.action}});"
  <> "document.getElementById('rerun').onclick=draw;document.getElementById('clear').onclick=draw;draw();"
  <> "</script></body></html>\n"
}

fn html_escape(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

fn firefox_smoke(screenshot_path: String) -> List(String) {
  let command =
    "timeout 25s firefox --headless --profile \"$PWD/build/cache/firefox-profile\" --screenshot \"$PWD/"
    <> screenshot_path
    <> "\" \"file://$PWD/build/playgrounds/browser-verify/index.html\" >/tmp/boon-gleam-firefox-smoke.log 2>&1"
  case
    background_launch.run_and_wait("browser-firefox-smoke", command, 30),
    file.is_file(screenshot_path)
  {
    True, True ->
      case file.file_size(screenshot_path) > 0 {
        True -> []
        False -> ["Firefox screenshot was created but empty"]
      }
    _, _ -> [
      "Firefox headless smoke did not produce a screenshot through cosmic-background-launch",
    ]
  }
}

fn command_succeeds(command: String) -> Bool {
  os_cmd(charlist.from_string("sh -c '" <> command <> "; echo EXIT:$?'"))
  |> charlist.to_string
  |> string.contains("EXIT:0")
}

fn list_append(left: List(String), right: List(String)) -> List(String) {
  case right {
    [] -> left
    _ -> list.append(left, right)
  }
}

fn html_response(body: String) -> Response(ResponseData) {
  response.new(200)
  |> response.prepend_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn json_response(status: Int, body: String) -> Response(ResponseData) {
  response.new(status)
  |> response.prepend_header("content-type", "application/json")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
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
          code: "browser_playground_io_failed",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "browser playground artifacts must be writable under build/playgrounds/browser",
        ),
      ])
  }
}

fn result_try_server(result, next) {
  case result {
    Ok(server) -> next(server)
    Error(_) ->
      Error([
        error(
          code: "browser_playground_server_failed",
          path: "browser",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "could not start browser playground server",
          help: "choose a different --port or stop the process already using the port",
        ),
      ])
  }
}
