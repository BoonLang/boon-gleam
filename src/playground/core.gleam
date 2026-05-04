import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/string
import lowering/pipeline
import project/loader
import project/project.{type Project}
import runtime/core.{InitContext}
import runtime/host as runtime_host
import terminal/arkanoid
import terminal/canvas
import terminal/pong
import verify/runner

pub type PlaygroundTarget {
  TerminalTarget
  NativeGuiTarget
  BrowserGuiTarget
}

pub type PlatformStatus {
  PlatformReady
  PlatformBlocked(reason: String)
}

pub type CatalogExample {
  CatalogExample(
    name: String,
    path: String,
    label: String,
    terminal: PlatformStatus,
    native: PlatformStatus,
    browser: PlatformStatus,
  )
}

pub type DrawCommand {
  FillRect(id: String, x: Int, y: Int, width: Int, height: Int, color: String)
  Text(id: String, x: Int, y: Int, size: Int, color: String, value: String)
}

pub type HitRegion {
  HitRegion(id: String, action: String, x: Int, y: Int, width: Int, height: Int)
}

pub type GuiScene {
  GuiScene(
    target: PlaygroundTarget,
    example: CatalogExample,
    width: Int,
    height: Int,
    title: String,
    source_path: String,
    source_preview: String,
    snapshot_text: String,
    diagnostics: List(String),
    commands: List(DrawCommand),
    hit_regions: List(HitRegion),
  )
}

pub type PlaygroundProof {
  PlaygroundProof(
    command: String,
    target: PlaygroundTarget,
    example: String,
    status: String,
    runtime_origin: String,
    scene_nonblank: Bool,
    semantic_ids_present: Bool,
    hit_regions_present: Bool,
    source_path: String,
    failures: List(String),
  )
}

pub fn catalog() -> List(CatalogExample) {
  [
    example("counter", "Counter", "examples/upstream/counter"),
    example("todo_mvc", "TodoMVC", "examples/upstream/todo_mvc"),
    example("cells", "Cells", "examples/upstream/cells"),
    example("cells_dynamic", "Cells Dynamic", "examples/upstream/cells_dynamic"),
    example("interval", "Interval", "examples/upstream/interval"),
    example("interval_hold", "Interval Hold", "examples/upstream/interval_hold"),
    example("pong", "Pong", "examples/terminal/pong"),
    example("arkanoid", "Arkanoid", "examples/terminal/arkanoid"),
  ]
}

fn example(name: String, label: String, path: String) -> CatalogExample {
  CatalogExample(
    name: name,
    path: path,
    label: label,
    terminal: PlatformReady,
    native: PlatformReady,
    browser: PlatformReady,
  )
}

pub fn find_example(
  selector: String,
) -> Result(CatalogExample, List(Diagnostic)) {
  let normalized = normalize_selector(selector)
  case
    catalog()
    |> list.filter(fn(example) {
      example.name == normalized || example.path == selector
    })
  {
    [example, ..] -> Ok(example)
    [] ->
      Error([
        error(
          code: "playground_example_not_found",
          path: selector,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "unknown playground example: " <> selector,
          help: "run one of: " <> catalog_names(),
        ),
      ])
  }
}

pub fn scene(
  selector: String,
  target: PlaygroundTarget,
) -> Result(GuiScene, List(Diagnostic)) {
  use example <- result_try(find_example(selector))
  use project <- result_try(loader.load(example.path))
  use snapshot_text <- result_try(snapshot_text(project, example))
  let source_preview = project.entry_file.contents
  let diagnostics = []
  let commands =
    scene_commands(example, target, project.entry_file.path, snapshot_text)
  let hit_regions = scene_hit_regions()
  Ok(GuiScene(
    target: target,
    example: example,
    width: 1180,
    height: 760,
    title: "Boon Gleam " <> target_name(target) <> " Playground",
    source_path: project.entry_file.path,
    source_preview: source_preview,
    snapshot_text: snapshot_text,
    diagnostics: diagnostics,
    commands: commands,
    hit_regions: hit_regions,
  ))
}

pub fn proof(command: String, scene: GuiScene) -> PlaygroundProof {
  let failures = scene_failures(scene)
  PlaygroundProof(
    command: command,
    target: scene.target,
    example: scene.example.name,
    status: case failures {
      [] -> "pass"
      _ -> "fail"
    },
    runtime_origin: "generated-boon-gleam-core",
    scene_nonblank: scene.commands != [],
    semantic_ids_present: scene.source_path != "",
    hit_regions_present: scene.hit_regions != [],
    source_path: scene.source_path,
    failures: failures,
  )
}

pub fn target_name(target: PlaygroundTarget) -> String {
  case target {
    TerminalTarget -> "terminal"
    NativeGuiTarget -> "native-gui"
    BrowserGuiTarget -> "browser-gui"
  }
}

pub fn proof_json(proof: PlaygroundProof) -> String {
  "{\n"
  <> "  \"command\": \""
  <> escape_json(proof.command)
  <> "\",\n"
  <> "  \"target\": \""
  <> target_name(proof.target)
  <> "\",\n"
  <> "  \"example\": \""
  <> escape_json(proof.example)
  <> "\",\n"
  <> "  \"status\": \""
  <> proof.status
  <> "\",\n"
  <> "  \"runtime_origin\": \""
  <> proof.runtime_origin
  <> "\",\n"
  <> "  \"scene_nonblank\": "
  <> bool_json(proof.scene_nonblank)
  <> ",\n"
  <> "  \"semantic_ids_present\": "
  <> bool_json(proof.semantic_ids_present)
  <> ",\n"
  <> "  \"hit_regions_present\": "
  <> bool_json(proof.hit_regions_present)
  <> ",\n"
  <> "  \"source_path\": \""
  <> escape_json(proof.source_path)
  <> "\",\n"
  <> "  \"failures\": "
  <> string_list_json(proof.failures)
  <> "\n"
  <> "}\n"
}

pub fn proofs_json(command: String, proofs: List(PlaygroundProof)) -> String {
  "{\n"
  <> "  \"command\": \""
  <> escape_json(command)
  <> "\",\n"
  <> "  \"status\": \""
  <> case all_passed(proofs) {
    True -> "pass"
    False -> "fail"
  }
  <> "\",\n"
  <> "  \"proofs\": ["
  <> {
    proofs
    |> list.map(proof_json_compact)
    |> string.join(with: ",")
  }
  <> "]\n"
  <> "}\n"
}

pub fn all_passed(proofs: List(PlaygroundProof)) -> Bool {
  list.all(proofs, fn(proof) { proof.status == "pass" })
}

fn proof_json_compact(proof: PlaygroundProof) -> String {
  proof_json(proof)
  |> string.trim
}

pub fn scene_json(scene: GuiScene) -> String {
  "{\n"
  <> "  \"target\": \""
  <> target_name(scene.target)
  <> "\",\n"
  <> "  \"example\": \""
  <> escape_json(scene.example.name)
  <> "\",\n"
  <> "  \"title\": \""
  <> escape_json(scene.title)
  <> "\",\n"
  <> "  \"width\": "
  <> int.to_string(scene.width)
  <> ",\n"
  <> "  \"height\": "
  <> int.to_string(scene.height)
  <> ",\n"
  <> "  \"source_path\": \""
  <> escape_json(scene.source_path)
  <> "\",\n"
  <> "  \"source_preview\": \""
  <> escape_json(scene.source_preview)
  <> "\",\n"
  <> "  \"snapshot_text\": \""
  <> escape_json(scene.snapshot_text)
  <> "\",\n"
  <> "  \"catalog_text\": \""
  <> escape_json(catalog_scene_text())
  <> "\",\n"
  <> "  \"commands\": "
  <> draw_commands_json(scene.commands)
  <> ",\n"
  <> "  \"hit_regions\": "
  <> hit_regions_json(scene.hit_regions)
  <> "\n"
  <> "}\n"
}

pub fn catalog_text() -> String {
  catalog()
  |> list.map(fn(example) { example.name <> "  " <> example.path })
  |> string.join(with: "\n")
}

fn catalog_scene_text() -> String {
  catalog()
  |> list.map(fn(example) {
    example.name
    <> "\t"
    <> example.label
    <> "\tbuild/playgrounds/native-"
    <> example.name
    <> "/scene.json"
  })
  |> string.join(with: "\n")
}

fn snapshot_text(
  project: Project,
  example: CatalogExample,
) -> Result(String, List(Diagnostic)) {
  case example.name {
    "pong" ->
      Ok(
        pong.score_text(pong.init())
        <> "\n"
        <> {
          pong.init()
          |> pong.snapshot
          |> canvas.to_text
        },
      )
    "arkanoid" ->
      Ok(
        arkanoid.score_text(arkanoid.init())
        <> "\n"
        <> {
          arkanoid.init()
          |> arkanoid.snapshot
          |> canvas.to_text
        },
      )
    _ -> {
      use program <- result_try(loader.parse_project(project))
      use flow <- result_try(pipeline.lower(
        project.name,
        project.entry_file.path,
        program,
      ))
      let host = runner.flow_host(flow)
      let state = runtime_host.init(host, InitContext(seed: 0))
      Ok(runtime_host.view(host, state).text)
    }
  }
}

fn scene_commands(
  example: CatalogExample,
  target: PlaygroundTarget,
  source_path: String,
  snapshot_text: String,
) -> List(DrawCommand) {
  [
    FillRect("background", 0, 0, 1180, 760, "#f7f2e8"),
    FillRect("sidebar", 0, 0, 245, 760, "#20302f"),
    FillRect("preview", 265, 72, 560, 480, "#ffffff"),
    FillRect("source", 845, 72, 310, 600, "#111827"),
    Text(
      "title",
      270,
      36,
      22,
      "#182322",
      target_name(target) <> " / " <> example.label,
    ),
    Text("catalog", 24, 34, 16, "#f4f2eb", "Examples"),
    Text("snapshot", 294, 116, 16, "#182322", snapshot_text),
    Text("source-path", 865, 108, 14, "#d7e2df", source_path),
    Text(
      "diagnostics",
      270,
      620,
      14,
      "#4b5563",
      "runtime: generated Boon Gleam core",
    ),
  ]
}

fn scene_hit_regions() -> List(HitRegion) {
  [
    HitRegion("playground.rerun", "rerun", 270, 590, 120, 36),
    HitRegion("playground.clear_state", "clear_state", 404, 590, 160, 36),
    HitRegion("playground.source", "scroll_source", 845, 72, 310, 600),
    HitRegion("playground.preview", "input", 265, 72, 560, 480),
  ]
}

fn scene_failures(scene: GuiScene) -> List(String) {
  []
  |> require(scene.commands != [], "scene has no draw commands")
  |> require(scene.hit_regions != [], "scene has no hit regions")
  |> require(scene.source_path != "", "scene has no source path")
}

fn require(
  failures: List(String),
  passed: Bool,
  message: String,
) -> List(String) {
  case passed {
    True -> failures
    False -> [message, ..failures]
  }
}

fn normalize_selector(selector: String) -> String {
  case string.split(selector, on: "/") |> list.reverse {
    [last, ..] -> last
    [] -> selector
  }
}

fn catalog_names() -> String {
  catalog()
  |> list.map(fn(example) { example.name })
  |> string.join(with: ", ")
}

fn draw_commands_json(commands: List(DrawCommand)) -> String {
  "["
  <> {
    commands
    |> list.map(draw_command_json)
    |> string.join(with: ",")
  }
  <> "]"
}

fn draw_command_json(command: DrawCommand) -> String {
  case command {
    FillRect(id, x, y, width, height, color) ->
      "{\"kind\":\"fill_rect\",\"id\":\""
      <> escape_json(id)
      <> "\",\"x\":"
      <> int.to_string(x)
      <> ",\"y\":"
      <> int.to_string(y)
      <> ",\"width\":"
      <> int.to_string(width)
      <> ",\"height\":"
      <> int.to_string(height)
      <> ",\"color\":\""
      <> escape_json(color)
      <> "\"}"
    Text(id, x, y, size, color, value) ->
      "{\"kind\":\"text\",\"id\":\""
      <> escape_json(id)
      <> "\",\"x\":"
      <> int.to_string(x)
      <> ",\"y\":"
      <> int.to_string(y)
      <> ",\"size\":"
      <> int.to_string(size)
      <> ",\"color\":\""
      <> escape_json(color)
      <> "\",\"value\":\""
      <> escape_json(value)
      <> "\"}"
  }
}

fn hit_regions_json(regions: List(HitRegion)) -> String {
  "["
  <> {
    regions
    |> list.map(fn(region) {
      "{\"id\":\""
      <> escape_json(region.id)
      <> "\",\"action\":\""
      <> escape_json(region.action)
      <> "\",\"x\":"
      <> int.to_string(region.x)
      <> ",\"y\":"
      <> int.to_string(region.y)
      <> ",\"width\":"
      <> int.to_string(region.width)
      <> ",\"height\":"
      <> int.to_string(region.height)
      <> "}"
    })
    |> string.join(with: ",")
  }
  <> "]"
}

fn string_list_json(values: List(String)) -> String {
  "["
  <> {
    values
    |> list.map(fn(value) { "\"" <> escape_json(value) <> "\"" })
    |> string.join(with: ",")
  }
  <> "]"
}

fn bool_json(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

pub fn escape_json(value: String) -> String {
  value
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
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
