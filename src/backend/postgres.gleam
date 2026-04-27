import backend/session
import frontend/diagnostic.{type Diagnostic, error}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor.{Started}
import gleam/string
import pog
import support/env
import support/file
import support/os

pub type PostgresReport {
  PostgresReport(
    example: String,
    project_id: String,
    session_id: String,
    sessions: Int,
    events: Int,
    event_results: Int,
    snapshots: Int,
  )
}

pub fn setup(database_url: String) -> Result(Nil, List(Diagnostic)) {
  use url <- result_try_database_url(database_url)
  use connection <- result_try_connection(url)
  use _ <- result_try_query(connection, sessions_schema())
  use _ <- result_try_query(connection, events_schema())
  use _ <- result_try_query(connection, event_results_schema())
  use _ <- result_try_query(connection, snapshot_schema())
  Ok(Nil)
}

pub fn verify_session(
  example_path: String,
  database_url: String,
) -> Result(PostgresReport, List(Diagnostic)) {
  use url <- result_try_database_url(database_url)
  use connection <- result_try_connection(url)
  use _ <- result_try_query(connection, sessions_schema())
  use _ <- result_try_query(connection, events_schema())
  use _ <- result_try_query(connection, event_results_schema())
  use _ <- result_try_query(connection, snapshot_schema())

  let project_id = session.project_id(example_path)
  let session_id = "postgres-smoke"
  use _ <- result_try_query(
    connection,
    delete_sql("boon_event_results", project_id, session_id),
  )
  use _ <- result_try_query(
    connection,
    delete_sql("boon_snapshots", project_id, session_id),
  )
  use _ <- result_try_query(
    connection,
    delete_sql("boon_events", project_id, session_id),
  )
  use _ <- result_try_query(
    connection,
    delete_sql("boon_sessions", project_id, session_id),
  )
  use _ <- result_try_query(
    connection,
    insert_session_sql(project_id, session_id, 1),
  )
  use _ <- result_try_query(
    connection,
    insert_event_sql(project_id, session_id, 1, "event-1", "click"),
  )
  use _ <- result_try_query(
    connection,
    insert_event_result_sql(
      project_id,
      session_id,
      "event-1",
      1,
      "postgres snapshot event:click#1",
    ),
  )
  use _ <- result_try_query(
    connection,
    insert_snapshot_sql(
      project_id,
      session_id,
      1,
      "postgres snapshot event:click#1",
    ),
  )

  use sessions <- result_try_count(
    connection,
    count_sql("boon_sessions", project_id, session_id),
  )
  use events <- result_try_count(
    connection,
    count_sql("boon_events", project_id, session_id),
  )
  use event_results <- result_try_count(
    connection,
    count_sql("boon_event_results", project_id, session_id),
  )
  use snapshots <- result_try_count(
    connection,
    count_sql("boon_snapshots", project_id, session_id),
  )
  let report =
    PostgresReport(
      example: example_path,
      project_id: project_id,
      session_id: session_id,
      sessions: sessions,
      events: events,
      event_results: event_results,
      snapshots: snapshots,
    )
  use _ <- result_try(write_report(report))
  Ok(report)
}

pub fn benchmark_events(
  example_path: String,
  database_url: String,
  events: Int,
) -> Result(List(Int), List(Diagnostic)) {
  use url <- result_try_database_url(database_url)
  use connection <- result_try_connection(url)
  use _ <- result_try_query(connection, sessions_schema())
  use _ <- result_try_query(connection, events_schema())
  use _ <- result_try_query(connection, event_results_schema())
  use _ <- result_try_query(connection, snapshot_schema())

  let project_id = session.project_id(example_path)
  let session_id = "postgres-bench"
  use _ <- result_try_query(
    connection,
    delete_sql("boon_event_results", project_id, session_id),
  )
  use _ <- result_try_query(
    connection,
    delete_sql("boon_snapshots", project_id, session_id),
  )
  use _ <- result_try_query(
    connection,
    delete_sql("boon_events", project_id, session_id),
  )
  use _ <- result_try_query(
    connection,
    delete_sql("boon_sessions", project_id, session_id),
  )
  use _ <- result_try_query(
    connection,
    insert_session_sql(project_id, session_id, 0),
  )
  benchmark_loop(connection, project_id, session_id, events, 1, [])
}

pub fn require_database_url() -> Result(String, List(Diagnostic)) {
  case env.get("DATABASE_URL") {
    Ok(value) -> validate_database_url(value)
    Error(_) -> database_url_missing()
  }
}

fn validate_database_url(
  database_url: String,
) -> Result(String, List(Diagnostic)) {
  case string.trim(database_url) {
    "" -> database_url_missing()
    value -> Ok(value)
  }
}

fn database_url_missing() -> Result(String, List(Diagnostic)) {
  Error([
    error(
      code: "database_url_missing",
      path: "DATABASE_URL",
      line: 1,
      column: 1,
      span_start: 0,
      span_end: 0,
      message: "Phase 9 PostgreSQL verification requires a non-empty DATABASE_URL",
      help: "export DATABASE_URL or pass `--database-url postgres://user:pass@host:5432/db`",
    ),
  ])
}

fn result_try_database_url(
  database_url: String,
  next: fn(String) -> Result(a, List(Diagnostic)),
) -> Result(a, List(Diagnostic)) {
  case validate_database_url(database_url) {
    Ok(value) -> next(value)
    Error(diagnostics) -> Error(diagnostics)
  }
}

fn result_try_connection(
  database_url: String,
  next: fn(pog.Connection) -> Result(a, List(Diagnostic)),
) -> Result(a, List(Diagnostic)) {
  let name = process.new_name(prefix: "boongleam_postgres")
  case pog.url_config(name, database_url) {
    Error(_) ->
      Error([
        error(
          code: "database_url_invalid",
          path: "DATABASE_URL",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "DATABASE_URL is not a valid postgres/postgresql URL",
          help: "use postgres://user:pass@host:5432/database",
        ),
      ])
    Ok(config) ->
      case pog.start(config) {
        Ok(Started(data: connection, ..)) -> next(connection)
        Error(_) ->
          Error([
            error(
              code: "postgres_pool_start_failed",
              path: "DATABASE_URL",
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: "could not start the pog PostgreSQL connection pool",
              help: "verify that the PostgreSQL service is reachable and credentials are valid",
            ),
          ])
      }
  }
}

fn result_try_query(
  connection: pog.Connection,
  sql: String,
  next: fn(pog.Returned(Nil)) -> Result(a, List(Diagnostic)),
) -> Result(a, List(Diagnostic)) {
  case pog.query(sql) |> pog.execute(on: connection) {
    Ok(returned) -> next(returned)
    Error(query_error) ->
      Error([
        error(
          code: "postgres_query_failed",
          path: "DATABASE_URL",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: query_error_message(query_error),
          help: "schema setup must be idempotent and the database user must be allowed to create tables",
        ),
      ])
  }
}

fn result_try_count(
  connection: pog.Connection,
  sql: String,
  next: fn(Int) -> Result(a, List(Diagnostic)),
) -> Result(a, List(Diagnostic)) {
  let decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  case pog.query(sql) |> pog.returning(decoder) |> pog.execute(on: connection) {
    Ok(pog.Returned(rows: [count, ..], ..)) -> next(count)
    Ok(_) ->
      Error([
        error(
          code: "postgres_count_missing",
          path: "DATABASE_URL",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "PostgreSQL verification count query returned no rows",
          help: "durable table verification must read back inserted rows",
        ),
      ])
    Error(query_error) ->
      Error([
        error(
          code: "postgres_query_failed",
          path: "DATABASE_URL",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: query_error_message(query_error),
          help: "PostgreSQL durability smoke must append and read event state",
        ),
      ])
  }
}

fn benchmark_loop(
  connection: pog.Connection,
  project_id: String,
  session_id: String,
  remaining: Int,
  revision: Int,
  samples: List(Int),
) -> Result(List(Int), List(Diagnostic)) {
  case remaining <= 0 {
    True -> Ok(list.reverse(samples))
    False -> {
      let started_at = os.monotonic_microsecond()
      let result =
        result_try_query(
          connection,
          append_event_tx_sql(project_id, session_id, revision),
          fn(_) { Ok(Nil) },
        )
      let finished_at = os.monotonic_microsecond()
      case result {
        Ok(_) ->
          benchmark_loop(
            connection,
            project_id,
            session_id,
            remaining - 1,
            revision + 1,
            [finished_at - started_at, ..samples],
          )
        Error(diagnostics) -> Error(diagnostics)
      }
    }
  }
}

fn write_report(report: PostgresReport) -> Result(Nil, List(Diagnostic)) {
  let path = "build/reports/postgres/" <> report.project_id <> ".json"
  case result_try_io(file.make_dir_all("build/reports/postgres")) {
    Error(diagnostics) -> Error(diagnostics)
    Ok(_) ->
      file.write_text_file(path, report_json(report))
      |> result_try_io
  }
}

fn report_json(report: PostgresReport) -> String {
  "{\n"
  <> "  \"example\": \""
  <> report.example
  <> "\",\n"
  <> "  \"project_id\": \""
  <> report.project_id
  <> "\",\n"
  <> "  \"session_id\": \""
  <> report.session_id
  <> "\",\n"
  <> "  \"sessions\": "
  <> int.to_string(report.sessions)
  <> ",\n"
  <> "  \"events\": "
  <> int.to_string(report.events)
  <> ",\n"
  <> "  \"event_results\": "
  <> int.to_string(report.event_results)
  <> ",\n"
  <> "  \"snapshots\": "
  <> int.to_string(report.snapshots)
  <> "\n"
  <> "}\n"
}

fn result_try_io(result: Result(a, String)) -> Result(a, List(Diagnostic)) {
  case result {
    Ok(value) -> Ok(value)
    Error(message) ->
      Error([
        error(
          code: "postgres_report_write_failed",
          path: "build/reports/postgres",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "PostgreSQL verification reports must be writable",
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
    Error(diagnostics) -> Error(diagnostics)
  }
}

fn query_error_message(query_error: pog.QueryError) -> String {
  case query_error {
    pog.ConstraintViolated(message, _, _) -> message
    pog.PostgresqlError(_, name, message) -> name <> ": " <> message
    pog.UnexpectedArgumentCount(expected, got) ->
      "unexpected argument count"
      <> " expected="
      <> int_to_string(expected)
      <> " got="
      <> int_to_string(got)
    pog.UnexpectedArgumentType(expected, got) ->
      "unexpected argument type expected=" <> expected <> " got=" <> got
    pog.UnexpectedResultType(_) -> "unexpected result type"
    pog.QueryTimeout -> "query timed out"
    pog.ConnectionUnavailable -> "connection unavailable"
  }
}

fn int_to_string(value: Int) -> String {
  int.to_string(value)
}

fn sessions_schema() -> String {
  "
CREATE TABLE IF NOT EXISTS boon_sessions (
  project_id text NOT NULL,
  session_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  current_revision bigint NOT NULL,
  PRIMARY KEY (project_id, session_id)
)
"
}

fn events_schema() -> String {
  "
CREATE TABLE IF NOT EXISTS boon_events (
  session_id text NOT NULL,
  project_id text NOT NULL,
  revision bigint NOT NULL,
  event_id text NOT NULL,
  event_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (project_id, session_id, revision),
  UNIQUE (project_id, session_id, event_id)
)
"
}

fn event_results_schema() -> String {
  "
CREATE TABLE IF NOT EXISTS boon_event_results (
  project_id text NOT NULL,
  session_id text NOT NULL,
  event_id text NOT NULL,
  revision bigint NOT NULL,
  result_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (project_id, session_id, event_id)
)
"
}

fn snapshot_schema() -> String {
  "
CREATE TABLE IF NOT EXISTS boon_snapshots (
  project_id text NOT NULL,
  session_id text NOT NULL,
  revision bigint NOT NULL,
  snapshot_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (project_id, session_id, revision)
)
"
}

fn delete_sql(table: String, project_id: String, session_id: String) -> String {
  "DELETE FROM "
  <> table
  <> " WHERE project_id = '"
  <> escape_sql(project_id)
  <> "' AND session_id = '"
  <> escape_sql(session_id)
  <> "'"
}

fn insert_session_sql(
  project_id: String,
  session_id: String,
  revision: Int,
) -> String {
  "INSERT INTO boon_sessions (project_id, session_id, current_revision) VALUES ('"
  <> escape_sql(project_id)
  <> "', '"
  <> escape_sql(session_id)
  <> "', "
  <> int.to_string(revision)
  <> ")"
}

fn insert_event_sql(
  project_id: String,
  session_id: String,
  revision: Int,
  event_id: String,
  event_type: String,
) -> String {
  "INSERT INTO boon_events (project_id, session_id, revision, event_id, event_json) VALUES ('"
  <> escape_sql(project_id)
  <> "', '"
  <> escape_sql(session_id)
  <> "', "
  <> int.to_string(revision)
  <> ", '"
  <> escape_sql(event_id)
  <> "', '{\"type\":\""
  <> escape_sql(event_type)
  <> "\"}'::jsonb)"
}

fn insert_event_result_sql(
  project_id: String,
  session_id: String,
  event_id: String,
  revision: Int,
  snapshot_text: String,
) -> String {
  "INSERT INTO boon_event_results (project_id, session_id, event_id, revision, result_json) VALUES ('"
  <> escape_sql(project_id)
  <> "', '"
  <> escape_sql(session_id)
  <> "', '"
  <> escape_sql(event_id)
  <> "', "
  <> int.to_string(revision)
  <> ", '{\"snapshot_text\":\""
  <> escape_sql(snapshot_text)
  <> "\"}'::jsonb)"
}

fn insert_snapshot_sql(
  project_id: String,
  session_id: String,
  revision: Int,
  snapshot_text: String,
) -> String {
  "INSERT INTO boon_snapshots (project_id, session_id, revision, snapshot_json) VALUES ('"
  <> escape_sql(project_id)
  <> "', '"
  <> escape_sql(session_id)
  <> "', "
  <> int.to_string(revision)
  <> ", '{\"text\":\""
  <> escape_sql(snapshot_text)
  <> "\",\"semantic_nodes\":[]}'::jsonb)"
}

fn append_event_tx_sql(
  project_id: String,
  session_id: String,
  revision: Int,
) -> String {
  let event_id = "bench-event-" <> int.to_string(revision)
  let snapshot_text =
    "postgres benchmark snapshot event:bench#" <> int.to_string(revision)
  "WITH inserted_event AS ("
  <> insert_event_sql(project_id, session_id, revision, event_id, "bench")
  <> " RETURNING revision), inserted_result AS ("
  <> insert_event_result_sql(
    project_id,
    session_id,
    event_id,
    revision,
    snapshot_text,
  )
  <> " RETURNING event_id), inserted_snapshot AS ("
  <> insert_snapshot_sql(project_id, session_id, revision, snapshot_text)
  <> " RETURNING revision) UPDATE boon_sessions SET current_revision = "
  <> int.to_string(revision)
  <> ", updated_at = now() WHERE project_id = '"
  <> escape_sql(project_id)
  <> "' AND session_id = '"
  <> escape_sql(session_id)
  <> "'"
}

fn count_sql(table: String, project_id: String, session_id: String) -> String {
  "SELECT count(*)::int FROM "
  <> table
  <> " WHERE project_id = '"
  <> escape_sql(project_id)
  <> "' AND session_id = '"
  <> escape_sql(session_id)
  <> "'"
}

fn escape_sql(value: String) -> String {
  value
  |> string.replace(each: "'", with: "''")
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: "\"", with: "\\\"")
}
