import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type StoreKind {
  Memory
  Local
  Postgres
}

pub type ProjectSessionId {
  ProjectSessionId(project_id: String, session_id: String)
}

pub type StoredEvent {
  StoredEvent(revision: Int, event_id: String, event_name: String)
}

pub type AppendedEvent {
  AppendedEvent(revision: Int, event_id: String)
}

pub type EventResult {
  EventResult(event_id: String, revision: Int, snapshot_text: String)
}

pub type StoredSnapshot {
  StoredSnapshot(revision: Int, snapshot_text: String)
}

pub type StoreError {
  RevisionConflict(current_revision: Int)
  StoreUnavailable(message: String)
}

pub type Store {
  Store(
    append_if_revision: fn(ProjectSessionId, Int, StoredEvent) ->
      Result(AppendedEvent, StoreError),
    load_events_after: fn(ProjectSessionId, Int) ->
      Result(List(StoredEvent), StoreError),
    load_event_result: fn(ProjectSessionId, String) ->
      Result(Option(EventResult), StoreError),
    save_event_result: fn(ProjectSessionId, String, EventResult) ->
      Result(Nil, StoreError),
    save_snapshot_tx: fn(ProjectSessionId, StoredSnapshot) ->
      Result(Nil, StoreError),
    load_latest_snapshot: fn(ProjectSessionId) ->
      Result(Option(StoredSnapshot), StoreError),
    clear_session: fn(ProjectSessionId) -> Result(Nil, StoreError),
  )
}

pub type BackendSession {
  BackendSession(
    id: ProjectSessionId,
    example: String,
    store: StoreKind,
    revision: Int,
    snapshot_text: String,
    events: List(StoredEvent),
    results: List(EventResult),
    snapshots: List(StoredSnapshot),
  )
}

pub fn start(
  example: String,
  store: StoreKind,
  snapshot_text: String,
) -> BackendSession {
  BackendSession(
    id: ProjectSessionId(project_id: project_id(example), session_id: "default"),
    example: example,
    store: store,
    revision: 0,
    snapshot_text: snapshot_text,
    events: [],
    results: [],
    snapshots: [StoredSnapshot(revision: 0, snapshot_text: snapshot_text)],
  )
}

pub fn dispatch(session: BackendSession, event_name: String) -> BackendSession {
  let event_id = event_name <> "-" <> int.to_string(session.revision + 1)
  case accept_event(session, event_id, session.revision, event_name) {
    Ok(#(next_session, _)) -> next_session
    Error(_) -> session
  }
}

pub fn accept_event(
  session: BackendSession,
  event_id: String,
  expected_revision: Int,
  event_name: String,
) -> Result(#(BackendSession, EventResult), StoreError) {
  case find_result(session.results, event_id) {
    Some(result) -> Ok(#(session, result))
    None ->
      case expected_revision == session.revision {
        False -> Error(RevisionConflict(current_revision: session.revision))
        True -> {
          let accepted_revision = session.revision + 1
          let snapshot_text =
            session.snapshot_text
            <> " event:"
            <> event_name
            <> "#"
            <> int.to_string(accepted_revision)
          let event =
            StoredEvent(
              revision: accepted_revision,
              event_id: event_id,
              event_name: event_name,
            )
          let result =
            EventResult(
              event_id: event_id,
              revision: accepted_revision,
              snapshot_text: snapshot_text,
            )
          let snapshot =
            StoredSnapshot(
              revision: accepted_revision,
              snapshot_text: snapshot_text,
            )
          Ok(#(
            BackendSession(
              ..session,
              revision: accepted_revision,
              snapshot_text: snapshot_text,
              events: list.append(session.events, [event]),
              results: list.append(session.results, [result]),
              snapshots: list.append(session.snapshots, [snapshot]),
            ),
            result,
          ))
        }
      }
  }
}

pub fn clear(session: BackendSession) -> BackendSession {
  BackendSession(
    ..session,
    revision: 0,
    snapshot_text: "",
    events: [],
    results: [],
    snapshots: [StoredSnapshot(revision: 0, snapshot_text: "")],
  )
}

pub fn recover(session: BackendSession) -> BackendSession {
  case latest_snapshot(session.snapshots) {
    Some(StoredSnapshot(revision: revision, snapshot_text: snapshot_text)) ->
      BackendSession(
        ..session,
        revision: revision,
        snapshot_text: snapshot_text,
      )
    None -> BackendSession(..session, revision: 0, snapshot_text: "")
  }
}

pub fn store_name(store: StoreKind) -> String {
  case store {
    Memory -> "memory"
    Local -> "local"
    Postgres -> "postgres"
  }
}

pub fn parse_store(value: String) -> StoreKind {
  case value {
    "local" -> Local
    "postgres" -> Postgres
    _ -> Memory
  }
}

pub fn is_postgres(store: StoreKind) -> Bool {
  case store {
    Postgres -> True
    _ -> False
  }
}

pub fn project_id(example: String) -> String {
  example
  |> string_parts
  |> list.last
  |> result_or(example)
}

fn find_result(
  results: List(EventResult),
  event_id: String,
) -> Option(EventResult) {
  case results {
    [] -> None
    [result, ..rest] ->
      case result.event_id == event_id {
        True -> Some(result)
        False -> find_result(rest, event_id)
      }
  }
}

fn latest_snapshot(snapshots: List(StoredSnapshot)) -> Option(StoredSnapshot) {
  case snapshots |> list.reverse |> list.first {
    Ok(snapshot) -> Some(snapshot)
    Error(_) -> None
  }
}

fn string_parts(value: String) -> List(String) {
  value
  |> string.split(on: "/")
  |> list.filter(fn(part) { part != "" })
}

fn result_or(result: Result(a, b), fallback: a) -> a {
  case result {
    Ok(value) -> value
    Error(_) -> fallback
  }
}
