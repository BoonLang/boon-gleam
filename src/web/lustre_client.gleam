import frontend/diagnostic.{type Diagnostic, error}
import gleam/list
import gleam/result
import gleam/string
import support/file

pub type WebReport {
  WebReport(example: String, mode: String, output_path: String)
}

pub fn build(
  example_path: String,
  mode: String,
) -> Result(WebReport, List(Diagnostic)) {
  case mode {
    "durable-client" | "local-js" -> {
      let out_dir = "build/generated/web_client"
      let src_dir = out_dir <> "/src/lustre_client"
      let out_path = out_dir <> "/src/lustre_client.gleam"
      case result_try_io(file.make_dir_all(src_dir)) {
        Error(diagnostics) -> Error(diagnostics)
        Ok(_) -> {
          use _ <- result_try(write_output(
            out_dir <> "/gleam.toml",
            package_toml(),
          ))
          use _ <- result_try(write_output(
            out_path,
            client_source(example_path, mode),
          ))
          use _ <- result_try(write_output(
            src_dir <> "/protocol.gleam",
            protocol_source(),
          ))
          use _ <- result_try(write_output(
            src_dir <> "/app.gleam",
            app_source(example_path, mode),
          ))
          use _ <- result_try(write_output(
            src_dir <> "/snapshot.gleam",
            snapshot_source(example_path),
          ))
          Ok(WebReport(example: example_path, mode: mode, output_path: out_path))
        }
      }
    }
    _ ->
      Error([
        error(
          code: "unsupported_web_mode",
          path: example_path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "web mode is not supported: " <> mode,
          help: "use `durable-client` or `local-js`",
        ),
      ])
  }
}

fn package_toml() -> String {
  "name = \"boongleam_web_client\"\n"
  <> "version = \"0.1.0\"\n"
  <> "target = \"erlang\"\n\n"
  <> "[dependencies]\n"
  <> "gleam_stdlib = \"1.0.0\"\n"
  <> "gleam_json = \"3.1.0\"\n"
  <> "lustre = \"5.6.0\"\n"
}

fn client_source(example_path: String, mode: String) -> String {
  "import gleam/json\n"
  <> "import lustre\n"
  <> "import lustre/element\n"
  <> "import lustre_client/app\n"
  <> "import lustre_client/protocol\n"
  <> "import lustre_client/snapshot\n\n"
  <> "pub const example = \""
  <> example_path
  <> "\"\n\n"
  <> "pub const mode = \""
  <> mode
  <> "\"\n\n"
  <> "pub fn init() { app.init() }\n\n"
  <> "pub fn render(model: app.Model) { snapshot.render(model.snapshot_text) }\n\n"
  <> "pub fn encode_event(event_id: String, expected_revision: Int, name: String) -> json.Json {\n"
  <> "  protocol.event(event_id, expected_revision, name)\n"
  <> "}\n\n"
  <> "pub fn marker() { element.none() }\n\n"
  <> "pub fn lustre_app() { lustre.element(marker()) }\n"
}

fn protocol_source() -> String {
  "import gleam/json\n\n"
  <> "pub fn subscribe() -> json.Json {\n"
  <> "  json.object([#(\"type\", json.string(\"subscribe\"))])\n"
  <> "}\n\n"
  <> "pub fn ping() -> json.Json {\n"
  <> "  json.object([#(\"type\", json.string(\"ping\"))])\n"
  <> "}\n\n"
  <> "pub fn get_snapshot() -> json.Json {\n"
  <> "  json.object([#(\"type\", json.string(\"get_snapshot\"))])\n"
  <> "}\n\n"
  <> "pub fn event(event_id: String, expected_revision: Int, name: String) -> json.Json {\n"
  <> "  json.object([\n"
  <> "    #(\"type\", json.string(\"event\")),\n"
  <> "    #(\"event_id\", json.string(event_id)),\n"
  <> "    #(\"expected_revision\", json.int(expected_revision)),\n"
  <> "    #(\"event\", json.object([#(\"type\", json.string(name))])),\n"
  <> "  ])\n"
  <> "}\n"
}

fn app_source(example_path: String, mode: String) -> String {
  "pub type Model {\n"
  <> "  Model(example: String, mode: String, revision: Int, snapshot_text: String)\n"
  <> "}\n\n"
  <> "pub type Msg {\n"
  <> "  SnapshotReceived(revision: Int, text: String)\n"
  <> "  EventAck(event_id: String, revision: Int)\n"
  <> "  EventRejected(event_id: String, reason: String)\n"
  <> "}\n\n"
  <> "pub fn init() -> Model {\n"
  <> "  Model(example: \""
  <> example_path
  <> "\", mode: \""
  <> mode
  <> "\", revision: 0, snapshot_text: \"\")\n"
  <> "}\n\n"
  <> "pub fn apply_snapshot(model: Model, revision: Int, text: String) -> Model {\n"
  <> "  Model(..model, revision: revision, snapshot_text: text)\n"
  <> "}\n"
}

fn snapshot_source(example_path: String) -> String {
  "pub const project_id = \""
  <> example_name(example_path)
  <> "\"\n\n"
  <> "pub fn render(text: String) -> String {\n"
  <> "  text\n"
  <> "}\n"
}

fn write_output(
  path: String,
  contents: String,
) -> Result(Nil, List(Diagnostic)) {
  file.write_text_file(path, contents)
  |> result_try_io
}

fn result_try_io(result: Result(a, String)) -> Result(a, List(Diagnostic)) {
  case result {
    Ok(value) -> Ok(value)
    Error(message) ->
      Error([
        error(
          code: "web_output_write_failed",
          path: "build/generated/web_client",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "web generated client artifacts must be writable",
        ),
      ])
  }
}

fn example_name(path: String) -> String {
  path
  |> string.split(on: "/")
  |> list.filter(fn(part) { part != "" })
  |> list.last
  |> result.unwrap(path)
}

fn result_try(
  result: Result(a, List(Diagnostic)),
  next: fn(a) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(errors) -> Error(errors)
  }
}
