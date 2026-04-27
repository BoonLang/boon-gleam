import backend/session
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import shelf
import shelf/set
import support/file

const base_directory = "build/state/shelf_store"

pub fn new() -> session.Store {
  session.Store(
    append_if_revision: append_if_revision,
    load_events_after: load_events_after,
    load_event_result: load_event_result,
    save_event_result: save_event_result,
    save_snapshot_tx: save_snapshot_tx,
    load_latest_snapshot: load_latest_snapshot,
    clear_session: clear_session,
  )
}

fn append_if_revision(
  id: session.ProjectSessionId,
  expected_revision: Int,
  event: session.StoredEvent,
) -> Result(session.AppendedEvent, session.StoreError) {
  use sessions <- with_table(id, "sessions.dets")
  let current_revision = current_session_revision(sessions, id)
  case current_revision == expected_revision {
    False -> Error(session.RevisionConflict(current_revision: current_revision))
    True -> {
      use events <- with_table(id, "events.dets")
      use _ <- result_try_shelf(set.insert(
        into: events,
        key: event_key(id, event.revision),
        value: event_value(event),
      ))
      use _ <- result_try_shelf(set.insert(
        into: sessions,
        key: session_key(id),
        value: int.to_string(event.revision),
      ))
      Ok(session.AppendedEvent(
        revision: event.revision,
        event_id: event.event_id,
      ))
    }
  }
}

fn load_events_after(
  id: session.ProjectSessionId,
  revision: Int,
) -> Result(List(session.StoredEvent), session.StoreError) {
  use events <- with_table(id, "events.dets")
  use entries <- result_try_shelf(set.to_list(from: events))
  entries
  |> list.filter_map(fn(entry) { parse_event_entry(id, revision, entry) })
  |> list.sort(compare_events)
  |> Ok
}

fn load_event_result(
  id: session.ProjectSessionId,
  event_id: String,
) -> Result(Option(session.EventResult), session.StoreError) {
  use results <- with_table(id, "event_results.dets")
  case set.lookup(from: results, key: event_result_key(id, event_id)) {
    Ok(value) -> Ok(parse_result_value(event_id, value))
    Error(shelf.NotFound) -> Ok(None)
    Error(error) -> Error(shelf_error(error))
  }
}

fn save_event_result(
  id: session.ProjectSessionId,
  event_id: String,
  event_result: session.EventResult,
) -> Result(Nil, session.StoreError) {
  use results <- with_table(id, "event_results.dets")
  set.insert(
    into: results,
    key: event_result_key(id, event_id),
    value: result_value(event_result),
  )
  |> map_shelf
}

fn save_snapshot_tx(
  id: session.ProjectSessionId,
  snapshot: session.StoredSnapshot,
) -> Result(Nil, session.StoreError) {
  use snapshots <- with_table(id, "snapshots.dets")
  set.insert(
    into: snapshots,
    key: snapshot_key(id, snapshot.revision),
    value: snapshot.snapshot_text,
  )
  |> map_shelf
}

fn load_latest_snapshot(
  id: session.ProjectSessionId,
) -> Result(Option(session.StoredSnapshot), session.StoreError) {
  use snapshots <- with_table(id, "snapshots.dets")
  use entries <- result_try_shelf(set.to_list(from: snapshots))
  entries
  |> list.filter_map(fn(entry) { parse_snapshot_entry(id, entry) })
  |> list.sort(compare_snapshots)
  |> latest_snapshot
  |> Ok
}

fn clear_session(
  id: session.ProjectSessionId,
) -> Result(Nil, session.StoreError) {
  use sessions <- with_table(id, "sessions.dets")
  use events <- with_table(id, "events.dets")
  use results <- with_table(id, "event_results.dets")
  use snapshots <- with_table(id, "snapshots.dets")
  use _ <- result_try_shelf(delete_matching(sessions, key_prefix(id)))
  use _ <- result_try_shelf(delete_matching(events, key_prefix(id)))
  use _ <- result_try_shelf(delete_matching(results, key_prefix(id)))
  use _ <- result_try_shelf(delete_matching(snapshots, key_prefix(id)))
  Ok(Nil)
}

fn with_table(
  id: session.ProjectSessionId,
  path: String,
  next: fn(set.PSet(String, String)) -> Result(a, session.StoreError),
) -> Result(a, session.StoreError) {
  case file.make_dir_all(session_directory(id)) {
    Error(message) -> Error(session.StoreUnavailable(message))
    Ok(_) -> {
      let table_path = session_table_path(id, path)
      let config =
        shelf.config(
          name: table_path,
          path: table_path,
          base_directory: base_directory,
        )
        |> shelf.write_mode(shelf.WriteThrough)
      case
        set.open_config(
          config: config,
          key: decode.string,
          value: decode.string,
        )
      {
        Error(error) -> Error(shelf_error(error))
        Ok(table) -> {
          let table_result = next(table)
          case table_result {
            Error(error) -> {
              let _ = set.close(table)
              Error(error)
            }
            Ok(value) ->
              case set.close(table) {
                Ok(_) -> Ok(value)
                Error(error) -> Error(shelf_error(error))
              }
          }
        }
      }
    }
  }
}

fn current_session_revision(
  table: set.PSet(String, String),
  id: session.ProjectSessionId,
) -> Int {
  case set.lookup(from: table, key: session_key(id)) {
    Ok(value) ->
      case int.parse(value) {
        Ok(revision) -> revision
        Error(_) -> 0
      }
    Error(_) -> 0
  }
}

fn delete_matching(
  table: set.PSet(String, String),
  prefix: String,
) -> Result(Nil, shelf.ShelfError) {
  use entries <- result_try_shelf_raw(set.to_list(from: table))
  let keys =
    entries
    |> list.map(fn(entry) { entry.0 })
    |> list.filter(fn(key) { string.starts_with(key, prefix) })
  delete_keys(table, keys)
}

fn delete_keys(
  table: set.PSet(String, String),
  keys: List(String),
) -> Result(Nil, shelf.ShelfError) {
  case keys {
    [] -> Ok(Nil)
    [key, ..rest] -> {
      use _ <- result_try_shelf_raw(set.delete_key(from: table, key: key))
      delete_keys(table, rest)
    }
  }
}

fn parse_event_entry(
  id: session.ProjectSessionId,
  after_revision: Int,
  entry: #(String, String),
) -> Result(session.StoredEvent, Nil) {
  case parse_revision_key(id, entry.0) {
    Some(revision) ->
      case revision > after_revision {
        False -> Error(Nil)
        True ->
          case string.split(entry.1, on: "\t") {
            [event_id, event_name] ->
              Ok(session.StoredEvent(
                revision: revision,
                event_id: event_id,
                event_name: event_name,
              ))
            _ -> Error(Nil)
          }
      }
    None -> Error(Nil)
  }
}

fn parse_snapshot_entry(
  id: session.ProjectSessionId,
  entry: #(String, String),
) -> Result(session.StoredSnapshot, Nil) {
  case parse_revision_key(id, entry.0) {
    Some(revision) ->
      Ok(session.StoredSnapshot(revision: revision, snapshot_text: entry.1))
    None -> Error(Nil)
  }
}

fn parse_result_value(
  event_id: String,
  value: String,
) -> Option(session.EventResult) {
  case string.split(value, on: "\t") {
    [revision_text, snapshot_text] ->
      case int.parse(revision_text) {
        Ok(revision) ->
          Some(session.EventResult(
            event_id: event_id,
            revision: revision,
            snapshot_text: snapshot_text,
          ))
        Error(_) -> None
      }
    _ -> None
  }
}

fn latest_snapshot(
  snapshots: List(session.StoredSnapshot),
) -> Option(session.StoredSnapshot) {
  case snapshots |> list.reverse |> list.first {
    Ok(snapshot) -> Some(snapshot)
    Error(_) -> None
  }
}

fn compare_events(
  left: session.StoredEvent,
  right: session.StoredEvent,
) -> order.Order {
  compare_int(left.revision, right.revision)
}

fn compare_snapshots(
  left: session.StoredSnapshot,
  right: session.StoredSnapshot,
) -> order.Order {
  compare_int(left.revision, right.revision)
}

fn compare_int(left: Int, right: Int) -> order.Order {
  case left < right {
    True -> order.Lt
    False ->
      case left > right {
        True -> order.Gt
        False -> order.Eq
      }
  }
}

fn session_key(id: session.ProjectSessionId) -> String {
  key_prefix(id) <> "session"
}

fn event_key(id: session.ProjectSessionId, revision: Int) -> String {
  key_prefix(id) <> "event:" <> int.to_string(revision)
}

fn event_result_key(id: session.ProjectSessionId, event_id: String) -> String {
  key_prefix(id) <> "result:" <> event_id
}

fn snapshot_key(id: session.ProjectSessionId, revision: Int) -> String {
  key_prefix(id) <> "snapshot:" <> int.to_string(revision)
}

fn key_prefix(id: session.ProjectSessionId) -> String {
  id.project_id <> "|" <> id.session_id <> "|"
}

fn session_directory(id: session.ProjectSessionId) -> String {
  base_directory
  <> "/"
  <> safe_path_part(id.project_id)
  <> "/"
  <> safe_path_part(id.session_id)
}

fn session_table_path(id: session.ProjectSessionId, path: String) -> String {
  safe_path_part(id.project_id)
  <> "/"
  <> safe_path_part(id.session_id)
  <> "/"
  <> path
}

fn safe_path_part(value: String) -> String {
  value
  |> string.replace(each: "/", with: "_")
  |> string.replace(each: "\\", with: "_")
  |> string.replace(each: ":", with: "_")
  |> string.replace(each: "|", with: "_")
  |> string.replace(each: " ", with: "_")
}

fn parse_revision_key(
  id: session.ProjectSessionId,
  key: String,
) -> Option(Int) {
  let prefix = key_prefix(id)
  case string.starts_with(key, prefix) {
    False -> None
    True -> {
      let suffix = string.drop_start(key, up_to: string.length(prefix))
      case string.split(suffix, on: ":") {
        [_kind, revision_text] ->
          case int.parse(revision_text) {
            Ok(revision) -> Some(revision)
            Error(_) -> None
          }
        _ -> None
      }
    }
  }
}

fn event_value(event: session.StoredEvent) -> String {
  event.event_id <> "\t" <> event.event_name
}

fn result_value(event_result: session.EventResult) -> String {
  int.to_string(event_result.revision) <> "\t" <> event_result.snapshot_text
}

fn shelf_error(error: shelf.ShelfError) -> session.StoreError {
  session.StoreUnavailable(shelf_error_message(error))
}

fn map_shelf(
  result: Result(a, shelf.ShelfError),
) -> Result(a, session.StoreError) {
  case result {
    Ok(value) -> Ok(value)
    Error(error) -> Error(shelf_error(error))
  }
}

fn result_try_shelf(
  result: Result(a, shelf.ShelfError),
  next: fn(a) -> Result(b, session.StoreError),
) -> Result(b, session.StoreError) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(shelf_error(error))
  }
}

fn result_try_shelf_raw(
  result: Result(a, shelf.ShelfError),
  next: fn(a) -> Result(b, shelf.ShelfError),
) -> Result(b, shelf.ShelfError) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}

fn shelf_error_message(error: shelf.ShelfError) -> String {
  case error {
    shelf.NotFound -> "not found"
    shelf.KeyAlreadyPresent -> "key already present"
    shelf.TableClosed -> "table closed"
    shelf.NotOwner -> "table owner mismatch"
    shelf.FileError(message) -> "file error: " <> message
    shelf.NameConflict -> "name conflict"
    shelf.InvalidPath(message) -> "invalid path: " <> message
    shelf.FileSizeLimitExceeded -> "file size limit exceeded"
    shelf.TypeMismatch(_) -> "type mismatch"
    shelf.ErlangError(message) -> "erlang error: " <> message
  }
}
