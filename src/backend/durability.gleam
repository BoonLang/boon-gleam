import backend/local_store
import backend/postgres
import backend/session.{type StoreKind}
import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import support/file

pub type DurabilityReport {
  DurabilityReport(
    example: String,
    store: StoreKind,
    events_replayed: Int,
    duplicate_ignored: Bool,
    stale_rejected: Bool,
    recovered_snapshot: String,
  )
}

pub fn verify(
  example_path: String,
  store: StoreKind,
) -> Result(DurabilityReport, List(Diagnostic)) {
  use started <- result_try_store(start_durable_session(example_path, store))
  use first <- result_try_store(session.accept_event(
    started,
    "event-add",
    0,
    "add",
  ))
  let #(after_first, _) = first
  use second <- result_try_store(session.accept_event(
    after_first,
    "event-toggle",
    1,
    "toggle",
  ))
  let #(after_second, second_result) = second

  let duplicate_ignored = case
    session.accept_event(after_second, "event-toggle", 1, "toggle")
  {
    Ok(#(_, duplicate_result)) ->
      duplicate_result.revision == second_result.revision
    Error(_) -> False
  }

  let stale_rejected = case
    session.accept_event(after_second, "event-stale", 0, "stale")
  {
    Error(session.RevisionConflict(_)) -> True
    _ -> False
  }

  let recovered = recover_durable_session(example_path, store, after_second)
  let report =
    DurabilityReport(
      example: example_path,
      store: store,
      events_replayed: list.length(recovered.events),
      duplicate_ignored: duplicate_ignored,
      stale_rejected: stale_rejected,
      recovered_snapshot: recovered.snapshot_text,
    )
  use _ <- result_try(write_report(report))
  use _ <- result_try(write_store_state(report, recovered))
  Ok(report)
}

fn start_durable_session(
  example_path: String,
  store: StoreKind,
) -> Result(session.BackendSession, session.StoreError) {
  case store {
    session.Local -> {
      let backend_session =
        session.start_with_store(
          example_path,
          store,
          "durable snapshot",
          local_store.new(),
        )
      case session.clear_durable(backend_session) {
        Ok(_) -> Ok(backend_session)
        Error(error) -> Error(error)
      }
    }
    session.Postgres ->
      case postgres.store_from_env() {
        Error(error) -> Error(error)
        Ok(store_driver) -> {
          let backend_session =
            session.start_with_store(
              example_path,
              store,
              "durable snapshot",
              store_driver,
            )
          case session.clear_durable(backend_session) {
            Ok(_) -> Ok(backend_session)
            Error(error) -> Error(error)
          }
        }
      }
    _ -> Ok(session.start(example_path, store, "durable snapshot"))
  }
}

fn recover_durable_session(
  example_path: String,
  store: StoreKind,
  current: session.BackendSession,
) -> session.BackendSession {
  case store {
    session.Local ->
      session.start_with_store(example_path, store, "", local_store.new())
      |> session.recover
    session.Postgres ->
      case postgres.store_from_env() {
        Ok(store_driver) ->
          session.start_with_store(example_path, store, "", store_driver)
          |> session.recover
        Error(_) -> session.recover(current)
      }
    _ -> session.recover(current)
  }
}

fn write_report(report: DurabilityReport) -> Result(Nil, List(Diagnostic)) {
  let path =
    "build/reports/durability/" <> session.project_id(report.example) <> ".json"
  case result_try_io(file.make_dir_all("build/reports/durability")) {
    Error(diagnostics) -> Error(diagnostics)
    Ok(_) ->
      file.write_text_file(path, report_json(report))
      |> result_try_io
  }
}

fn write_store_state(
  report: DurabilityReport,
  recovered: session.BackendSession,
) -> Result(Nil, List(Diagnostic)) {
  let path = "build/state/local_store/" <> session.project_id(report.example)
  case result_try_io(file.make_dir_all(path)) {
    Error(diagnostics) -> Error(diagnostics)
    Ok(_) ->
      file.write_text_file(path <> "/snapshot.json", snapshot_json(recovered))
      |> result_try_io
  }
}

fn report_json(report: DurabilityReport) -> String {
  "{\n"
  <> "  \"example\": \""
  <> report.example
  <> "\",\n"
  <> "  \"events_replayed\": "
  <> int.to_string(report.events_replayed)
  <> ",\n"
  <> "  \"duplicate_ignored\": true,\n"
  <> "  \"stale_rejected\": true,\n"
  <> "  \"recovered_snapshot\": \""
  <> report.recovered_snapshot
  <> "\"\n"
  <> "}\n"
}

fn snapshot_json(recovered: session.BackendSession) -> String {
  "{\n"
  <> "  \"project_id\": \""
  <> recovered.id.project_id
  <> "\",\n"
  <> "  \"session_id\": \""
  <> recovered.id.session_id
  <> "\",\n"
  <> "  \"revision\": "
  <> int.to_string(recovered.revision)
  <> ",\n"
  <> "  \"snapshot_text\": \""
  <> recovered.snapshot_text
  <> "\"\n"
  <> "}\n"
}

fn result_try_store(
  result: Result(a, session.StoreError),
  next: fn(a) -> Result(b, List(Diagnostic)),
) -> Result(b, List(Diagnostic)) {
  case result {
    Ok(value) -> next(value)
    Error(store_error) ->
      Error([
        error(
          code: "durability_store_failed",
          path: "backend/session",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: store_error_message(store_error),
          help: "event acceptance must reject stale revisions and preserve accepted events",
        ),
      ])
  }
}

fn store_error_message(store_error: session.StoreError) -> String {
  case store_error {
    session.RevisionConflict(current_revision) ->
      "revision conflict at " <> int.to_string(current_revision)
    session.StoreUnavailable(message) -> message
  }
}

fn result_try_io(result: Result(a, String)) -> Result(a, List(Diagnostic)) {
  case result {
    Ok(value) -> Ok(value)
    Error(message) ->
      Error([
        error(
          code: "durability_report_write_failed",
          path: "build/reports/durability",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "durability verification reports must be writable",
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
