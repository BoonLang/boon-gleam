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
    store_driver: Option(Store),
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
    store_driver: None,
  )
}

pub fn start_with_store(
  example: String,
  store: StoreKind,
  snapshot_text: String,
  store_driver: Store,
) -> BackendSession {
  let started = start(example, store, snapshot_text)
  BackendSession(..started, store_driver: Some(store_driver))
}

pub fn attach_store(
  backend_session: BackendSession,
  store_driver: Store,
) -> BackendSession {
  BackendSession(..backend_session, store_driver: Some(store_driver))
}

pub fn detach_store(backend_session: BackendSession) -> BackendSession {
  BackendSession(..backend_session, store_driver: None)
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
      case load_stored_result(session, event_id) {
        Ok(Some(result)) -> Ok(#(cache_result(session, result), result))
        Ok(None) ->
          accept_new_event(session, event_id, expected_revision, event_name)
        Error(error) -> Error(error)
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

pub fn clear_durable(
  session: BackendSession,
) -> Result(BackendSession, StoreError) {
  case session.store_driver {
    None -> Ok(clear(session))
    Some(store) ->
      case store.clear_session(session.id) {
        Ok(_) -> Ok(clear(session))
        Error(error) -> Error(error)
      }
  }
}

pub fn recover(session: BackendSession) -> BackendSession {
  case session.store_driver {
    Some(store) ->
      case store.load_latest_snapshot(session.id) {
        Ok(Some(StoredSnapshot(revision: revision, snapshot_text: snapshot_text))) -> {
          let events = case store.load_events_after(session.id, 0) {
            Ok(events) -> events
            Error(_) -> session.events
          }
          BackendSession(
            ..session,
            revision: revision,
            snapshot_text: snapshot_text,
            events: events,
          )
        }
        _ -> recover_memory(session)
      }
    None -> recover_memory(session)
  }
}

fn recover_memory(session: BackendSession) -> BackendSession {
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

fn accept_new_event(
  session: BackendSession,
  event_id: String,
  expected_revision: Int,
  event_name: String,
) -> Result(#(BackendSession, EventResult), StoreError) {
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
      use _ <- result_try_store(persist_event(
        session,
        expected_revision,
        event,
        result,
        snapshot,
      ))
      Ok(#(apply_accepted_event(session, event, result, snapshot), result))
    }
  }
}

fn persist_event(
  session: BackendSession,
  expected_revision: Int,
  event: StoredEvent,
  result: EventResult,
  snapshot: StoredSnapshot,
) -> Result(Nil, StoreError) {
  case session.store_driver {
    None -> Ok(Nil)
    Some(store) -> {
      use _ <- result_try_store(store.append_if_revision(
        session.id,
        expected_revision,
        event,
      ))
      use _ <- result_try_store(store.save_event_result(
        session.id,
        event.event_id,
        result,
      ))
      store.save_snapshot_tx(session.id, snapshot)
    }
  }
}

fn load_stored_result(
  session: BackendSession,
  event_id: String,
) -> Result(Option(EventResult), StoreError) {
  case session.store_driver {
    None -> Ok(None)
    Some(store) -> store.load_event_result(session.id, event_id)
  }
}

fn cache_result(
  session: BackendSession,
  result: EventResult,
) -> BackendSession {
  BackendSession(
    ..session,
    revision: result.revision,
    snapshot_text: result.snapshot_text,
    results: list.append(session.results, [result]),
  )
}

fn apply_accepted_event(
  session: BackendSession,
  event: StoredEvent,
  result: EventResult,
  snapshot: StoredSnapshot,
) -> BackendSession {
  BackendSession(
    ..session,
    revision: snapshot.revision,
    snapshot_text: snapshot.snapshot_text,
    events: list.append(session.events, [event]),
    results: list.append(session.results, [result]),
    snapshots: list.append(session.snapshots, [snapshot]),
  )
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

fn result_try_store(
  result: Result(a, StoreError),
  next: fn(a) -> Result(b, StoreError),
) -> Result(b, StoreError) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
