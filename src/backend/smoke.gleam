import backend/session.{type StoreKind}
import frontend/diagnostic.{type Diagnostic, error}
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import mist.{type Connection, type ResponseData}
import support/file
import support/http as http_client

pub type BackendReport {
  BackendReport(
    example: String,
    store: StoreKind,
    port: Int,
    timeout_ms: Int,
    revision: Int,
    snapshot_text: String,
    health_status: Int,
    session_status: Int,
    snapshot_status: Int,
    events_status: Int,
    clear_status: Int,
    websocket_trace: List(String),
  )
}

pub fn serve_smoke(
  example_path: String,
  store: StoreKind,
  port: Int,
  timeout_ms: Int,
) -> Result(BackendReport, List(Diagnostic)) {
  let actual_port = case port {
    0 -> 18_080
    _ -> port
  }
  let session =
    session.start(example_path, store, "backend session ready")
    |> session.dispatch("connect")
    |> session.dispatch("snapshot")

  use _server <- result_try_server(start_server(
    example_path,
    store,
    actual_port,
    session,
  ))
  use health <- result_try_http(http_client.request(
    "GET",
    base_url(actual_port) <> "/health",
    "",
  ))
  use project <- result_try_http(http_client.request(
    "POST",
    base_url(actual_port) <> "/projects",
    "{\"project_id\":\""
      <> session.id.project_id
      <> "\",\"source_path\":\""
      <> example_path
      <> "\"}",
  ))
  use session_response <- result_try_http(http_client.request(
    "POST",
    base_url(actual_port)
      <> "/projects/"
      <> session.id.project_id
      <> "/sessions",
    "{\"session_id\":\"" <> session.id.session_id <> "\"}",
  ))
  use snapshot <- result_try_http(http_client.request(
    "GET",
    base_url(actual_port)
      <> "/projects/"
      <> session.id.project_id
      <> "/sessions/"
      <> session.id.session_id
      <> "/snapshot",
    "",
  ))
  use events <- result_try_http(http_client.request(
    "GET",
    base_url(actual_port)
      <> "/projects/"
      <> session.id.project_id
      <> "/sessions/"
      <> session.id.session_id
      <> "/events",
    "",
  ))
  use clear <- result_try_http(http_client.request(
    "POST",
    base_url(actual_port)
      <> "/projects/"
      <> session.id.project_id
      <> "/sessions/"
      <> session.id.session_id
      <> "/clear",
    "",
  ))

  use _ <- result_try(validate_status("health", health, 200))
  use _ <- result_try(validate_status("project", project, 201))
  use _ <- result_try(validate_status("session", session_response, 201))
  use _ <- result_try(validate_status("snapshot", snapshot, 200))
  use _ <- result_try(validate_status("events", events, 200))
  use _ <- result_try(validate_status("clear", clear, 200))
  use websocket_trace <- result_try_websocket(http_client.websocket_smoke(
    "127.0.0.1",
    actual_port,
    "/ws/projects/"
      <> session.id.project_id
      <> "/sessions/"
      <> session.id.session_id,
    websocket_messages(session),
  ))
  use _ <- result_try(validate_websocket_trace(websocket_trace))

  let report =
    BackendReport(
      example: example_path,
      store: store,
      port: actual_port,
      timeout_ms: timeout_ms,
      revision: session.revision,
      snapshot_text: session.snapshot_text,
      health_status: health.0,
      session_status: session_response.0,
      snapshot_status: snapshot.0,
      events_status: events.0,
      clear_status: clear.0,
      websocket_trace: websocket_trace,
    )
  use _ <- result_try(write_report(report, "build/reports/backend/counter.json"))
  Ok(report)
}

pub fn verify_backend(
  example_path: String,
  store: StoreKind,
) -> Result(BackendReport, List(Diagnostic)) {
  serve_smoke(example_path, store, 18_080, 5000)
}

pub fn serve(
  example_path: String,
  store: StoreKind,
  port: Int,
) -> Result(Nil, List(Diagnostic)) {
  let backend_session =
    session.start(example_path, store, "backend session ready")
  use _server <- result_try_server(start_server(
    example_path,
    store,
    port,
    backend_session,
  ))
  process.sleep_forever()
  Ok(Nil)
}

fn start_server(
  example_path: String,
  store: StoreKind,
  port: Int,
  backend_session: session.BackendSession,
) {
  fn(request) { handle_request(example_path, store, backend_session, request) }
  |> mist.new
  |> mist.bind("127.0.0.1")
  |> mist.port(port)
  |> mist.after_start(fn(_, _, _) { Nil })
  |> mist.start
}

fn handle_request(
  example_path: String,
  _store: StoreKind,
  backend_session: session.BackendSession,
  request: Request(Connection),
) -> Response(ResponseData) {
  let project_id = backend_session.id.project_id
  let session_id = backend_session.id.session_id
  case request.method, request.path_segments(request) {
    Get, ["health"] -> json_response(200, "{\"status\":\"ok\"}")
    Get, ["projects"] ->
      json_response(
        200,
        "{\"projects\":[{\"project_id\":\""
          <> project_id
          <> "\",\"entry\":\""
          <> entry_name(example_path)
          <> "\"}]}",
      )
    Post, ["projects"] ->
      json_response(201, "{\"project_id\":\"" <> project_id <> "\"}")
    Get, ["projects", requested_project] ->
      case requested_project == project_id {
        True ->
          json_response(
            200,
            "{\"project_id\":\""
              <> project_id
              <> "\",\"compiled\":true,\"diagnostics\":[]}",
          )
        False -> not_found("project_not_found")
      }
    Post, ["projects", requested_project, "compile"] ->
      case requested_project == project_id {
        True ->
          json_response(
            200,
            "{\"project_id\":\"" <> project_id <> "\",\"diagnostics\":[]}",
          )
        False -> not_found("project_not_found")
      }
    Post, ["projects", requested_project, "sessions"] ->
      case requested_project == project_id {
        True ->
          json_response(
            201,
            "{\"project_id\":\""
              <> project_id
              <> "\",\"session_id\":\""
              <> session_id
              <> "\",\"revision\":0}",
          )
        False -> not_found("project_not_found")
      }
    Get,
      ["projects", requested_project, "sessions", requested_session, "snapshot"]
    ->
      case requested_project == project_id && requested_session == session_id {
        True ->
          json_response(
            200,
            "{\"revision\":"
              <> int.to_string(backend_session.revision)
              <> ",\"snapshot\":{\"text\":\""
              <> escape_json(backend_session.snapshot_text)
              <> "\",\"semantic_nodes\":[]}}",
          )
        False -> not_found("session_not_found")
      }
    Get,
      ["projects", requested_project, "sessions", requested_session, "events"]
    ->
      case requested_project == project_id && requested_session == session_id {
        True ->
          json_response(
            200,
            "{\"events\":" <> events_json(backend_session) <> "}",
          )
        False -> not_found("session_not_found")
      }
    Post,
      ["projects", requested_project, "sessions", requested_session, "clear"]
    ->
      case requested_project == project_id && requested_session == session_id {
        True -> json_response(200, "{\"cleared\":true}")
        False -> not_found("session_not_found")
      }
    Get, ["ws", "projects", requested_project, "sessions", requested_session] ->
      case requested_project == project_id && requested_session == session_id {
        True ->
          mist.websocket(
            request: request,
            on_init: fn(_connection) { #(backend_session, None) },
            on_close: fn(_state) { Nil },
            handler: handle_ws_message,
          )
        False -> not_found("session_not_found")
      }
    _, _ -> not_found("route_not_found")
  }
}

fn json_response(status: Int, body: String) -> Response(ResponseData) {
  response.new(status)
  |> response.prepend_header("content-type", "application/json")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn not_found(code: String) -> Response(ResponseData) {
  json_response(
    404,
    "{\"error\":{\"code\":\"" <> code <> "\",\"message\":\"not found\"}}",
  )
}

fn handle_ws_message(
  state: session.BackendSession,
  message: mist.WebsocketMessage(Nil),
  connection: mist.WebsocketConnection,
) -> mist.Next(session.BackendSession, Nil) {
  case message {
    mist.Text(text) -> handle_ws_text(state, text, connection)
    mist.Binary(_) -> mist.continue(state)
    mist.Custom(_) -> mist.continue(state)
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn handle_ws_text(
  state: session.BackendSession,
  text: String,
  connection: mist.WebsocketConnection,
) -> mist.Next(session.BackendSession, Nil) {
  case
    string.contains(text, "\"type\":\"subscribe\"")
    || string.contains(text, "\"type\": \"subscribe\"")
  {
    True -> {
      let _ = mist.send_text_frame(connection, ws_snapshot(state))
      mist.continue(state)
    }
    False ->
      case
        string.contains(text, "\"type\":\"get_snapshot\"")
        || string.contains(text, "\"type\": \"get_snapshot\"")
      {
        True -> {
          let _ = mist.send_text_frame(connection, ws_snapshot(state))
          mist.continue(state)
        }
        False ->
          case
            string.contains(text, "\"type\":\"ping\"")
            || string.contains(text, "\"type\": \"ping\"")
          {
            True -> {
              let _ = mist.send_text_frame(connection, "{\"type\":\"pong\"}")
              mist.continue(state)
            }
            False -> handle_ws_event(state, text, connection)
          }
      }
  }
}

fn handle_ws_event(
  state: session.BackendSession,
  text: String,
  connection: mist.WebsocketConnection,
) -> mist.Next(session.BackendSession, Nil) {
  case
    string.contains(text, "\"type\":\"event\"")
    || string.contains(text, "\"type\": \"event\"")
  {
    False -> mist.continue(state)
    True ->
      case
        session.accept_event(
          state,
          "ws-event-" <> int.to_string(state.revision + 1),
          state.revision,
          "websocket",
        )
      {
        Ok(#(next_state, result)) -> {
          let _ =
            mist.send_text_frame(
              connection,
              "{\"type\":\"event_ack\",\"event_id\":\""
                <> result.event_id
                <> "\",\"revision\":"
                <> int.to_string(result.revision)
                <> "}",
            )
          let _ = mist.send_text_frame(connection, ws_snapshot(next_state))
          mist.continue(next_state)
        }
        Error(session.RevisionConflict(current_revision)) -> {
          let _ =
            mist.send_text_frame(
              connection,
              "{\"type\":\"event_reject\",\"event_id\":\"unknown\",\"reason\":\"revision_conflict\",\"current_revision\":"
                <> int.to_string(current_revision)
                <> "}",
            )
          mist.continue(state)
        }
        Error(session.StoreUnavailable(message)) -> {
          let _ =
            mist.send_text_frame(
              connection,
              "{\"type\":\"diagnostic\",\"diagnostic\":{\"message\":\""
                <> escape_json(message)
                <> "\"}}",
            )
          mist.continue(state)
        }
      }
  }
}

fn ws_snapshot(state: session.BackendSession) -> String {
  "{\"type\":\"snapshot\",\"revision\":"
  <> int.to_string(state.revision)
  <> ",\"snapshot\":{\"text\":\""
  <> escape_json(state.snapshot_text)
  <> "\",\"semantic_nodes\":[]}}"
}

fn write_report(
  report: BackendReport,
  path: String,
) -> Result(Nil, List(Diagnostic)) {
  case result_try_io(file.make_dir_all("build/reports/backend")) {
    Error(diagnostics) -> Error(diagnostics)
    Ok(_) ->
      file.write_text_file(path, report_json(report))
      |> result_try_io
  }
}

fn report_json(report: BackendReport) -> String {
  "{\n"
  <> "  \"example\": \""
  <> report.example
  <> "\",\n"
  <> "  \"store\": \""
  <> session.store_name(report.store)
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
  <> report.snapshot_text
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
  <> ",\n"
  <> "  \"websocket_trace\": ["
  <> string.join(
    list.map(report.websocket_trace, fn(message) {
      "\"" <> escape_json(message) <> "\""
    }),
    with: ", ",
  )
  <> "]\n"
  <> "}\n"
}

fn validate_status(
  name: String,
  result: #(Int, String),
  expected: Int,
) -> Result(Nil, List(Diagnostic)) {
  case result.0 == expected {
    True -> Ok(Nil)
    False ->
      Error([
        error(
          code: "backend_smoke_status_mismatch",
          path: name,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "expected HTTP "
            <> int.to_string(expected)
            <> " but got "
            <> int.to_string(result.0)
            <> " body="
            <> result.1,
          help: "serve-smoke must satisfy the backend API schema",
        ),
      ])
  }
}

fn result_try_server(
  result,
  next: fn(a) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(started) -> next(started)
    Error(_) ->
      Error([
        error(
          code: "backend_server_start_failed",
          path: "serve-smoke",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "could not start bounded Mist backend server",
          help: "check whether the requested port is already in use",
        ),
      ])
  }
}

fn result_try_http(
  result: Result(#(Int, String), String),
  next: fn(#(Int, String)) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(message) ->
      Error([
        error(
          code: "backend_http_smoke_failed",
          path: "serve-smoke",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "bounded backend smoke must reach the Mist HTTP server",
        ),
      ])
  }
}

fn base_url(port: Int) -> String {
  "http://127.0.0.1:" <> int.to_string(port)
}

fn websocket_messages(backend_session: session.BackendSession) -> List(String) {
  [
    "{\"type\":\"subscribe\"}",
    "{\"type\":\"ping\"}",
    "{\"type\":\"event\",\"event_id\":\"ws-event\",\"expected_revision\":"
      <> int.to_string(backend_session.revision)
      <> ",\"event\":{\"type\":\"click\",\"link_id\":\"counter.increment\"}}",
    "{\"type\":\"get_snapshot\"}",
  ]
}

fn validate_websocket_trace(
  frames: List(String),
) -> Result(Nil, List(Diagnostic)) {
  let joined = string.join(frames, with: "\n")
  case
    string.contains(joined, "\"type\":\"snapshot\"")
    && string.contains(joined, "\"type\":\"pong\"")
    && string.contains(joined, "\"type\":\"event_ack\"")
  {
    True -> Ok(Nil)
    False ->
      Error([
        error(
          code: "backend_websocket_smoke_failed",
          path: "serve-smoke",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "WebSocket smoke did not receive snapshot, pong, and event_ack frames",
          help: "the WebSocket protocol must satisfy fixtures/protocol_schema.json",
        ),
      ])
  }
}

fn result_try_websocket(
  result: Result(List(String), String),
  next: fn(List(String)) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(message) ->
      Error([
        error(
          code: "backend_websocket_smoke_failed",
          path: "serve-smoke",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "bounded backend smoke must complete a real WebSocket handshake and frame exchange",
        ),
      ])
  }
}

fn events_json(backend_session: session.BackendSession) -> String {
  "["
  <> string.join(
    list.map(backend_session.events, fn(event) {
      "{\"revision\":"
      <> int.to_string(event.revision)
      <> ",\"event_id\":\""
      <> event.event_id
      <> "\",\"event\":{\"type\":\""
      <> event.event_name
      <> "\"}}"
    }),
    with: ",",
  )
  <> "]"
}

fn entry_name(example_path: String) -> String {
  session.project_id(example_path) <> ".bn"
}

fn escape_json(value: String) -> String {
  value
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: "\"", with: "\\\"")
}

fn result_try_io(result: Result(a, String)) -> Result(a, List(Diagnostic)) {
  case result {
    Ok(value) -> Ok(value)
    Error(message) ->
      Error([
        error(
          code: "backend_report_write_failed",
          path: "build/reports/backend/counter.json",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "backend smoke reports must be writable",
        ),
      ])
  }
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
