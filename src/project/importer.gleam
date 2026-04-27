import frontend/diagnostic.{type Diagnostic, error}
import gleam/int
import gleam/list
import gleam/string
import support/file

pub type ImportReport {
  ImportReport(source_root: String, out_root: String, examples: Int, files: Int)
}

pub fn import_upstream(
  source: String,
  out_root: String,
) -> Result(ImportReport, List(Diagnostic)) {
  let source_root = source_root(source)
  case file.is_directory(source_root) {
    False ->
      Error([
        error(
          code: "import_source_missing",
          path: source,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "source corpus root does not exist: " <> source_root,
          help: "pass either the Boon repo root or playground/frontend/src/examples",
        ),
      ])
    True -> copy_examples(source_root, out_root)
  }
}

fn copy_examples(
  source_root: String,
  out_root: String,
) -> Result(ImportReport, List(Diagnostic)) {
  use copied <- result_try(copy_example_loop(
    source_root,
    out_root,
    examples(),
    0,
  ))
  Ok(ImportReport(
    source_root: source_root,
    out_root: out_root,
    examples: list.length(examples()),
    files: copied,
  ))
}

fn copy_example_loop(
  source_root: String,
  out_root: String,
  examples: List(String),
  copied: Int,
) -> Result(Int, List(Diagnostic)) {
  case examples {
    [] -> Ok(copied)
    [example, ..rest] -> {
      let source_path = source_root <> "/" <> example
      let out_path = out_root <> "/" <> example
      case file.is_directory(source_path) {
        False ->
          Error([
            error(
              code: "import_example_missing",
              path: source_path,
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: "manifest example is missing from source corpus: "
                <> example,
              help: "use the pinned Boon corpus commit or update the manifest explicitly",
            ),
          ])
        True -> {
          use count <- result_try(copy_tree(source_path, out_path))
          copy_example_loop(source_root, out_root, rest, copied + count)
        }
      }
    }
  }
}

fn copy_tree(
  source_path: String,
  out_path: String,
) -> Result(Int, List(Diagnostic)) {
  case file.list_files_recursive(source_path) {
    Error(message) ->
      Error([
        error(
          code: "import_list_failed",
          path: source_path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "source corpus directories must be readable",
        ),
      ])
    Ok(paths) -> copy_file_loop(source_path, out_path, paths, 0)
  }
}

fn copy_file_loop(
  source_root: String,
  out_root: String,
  paths: List(String),
  copied: Int,
) -> Result(Int, List(Diagnostic)) {
  case paths {
    [] -> Ok(copied)
    [path, ..rest] -> {
      let relative = relative_to(source_root, path)
      let destination = out_root <> "/" <> relative
      case file.copy_file(path, destination) {
        Ok(_) -> copy_file_loop(source_root, out_root, rest, copied + 1)
        Error(message) ->
          Error([
            error(
              code: "import_copy_failed",
              path: path,
              line: 1,
              column: 1,
              span_start: 0,
              span_end: 0,
              message: message,
              help: "import-upstream must preserve corpus files byte-for-byte",
            ),
          ])
      }
    }
  }
}

fn source_root(source: String) -> String {
  let repo_examples = source <> "/playground/frontend/src/examples"
  case file.is_directory(repo_examples) {
    True -> repo_examples
    False -> trim_trailing_slash(source)
  }
}

fn examples() -> List(String) {
  [
    "minimal",
    "hello_world",
    "counter",
    "counter_hold",
    "complex_counter",
    "shopping_list",
    "todo_mvc",
    "todo_mvc_physical",
  ]
}

fn relative_to(root: String, path: String) -> String {
  let prefix = trim_trailing_slash(root) <> "/"
  case string.starts_with(path, prefix) {
    True -> string.drop_start(path, up_to: string.length(prefix))
    False -> path
  }
}

fn trim_trailing_slash(path: String) -> String {
  case string.ends_with(path, "/") {
    True -> string.drop_end(path, up_to: 1)
    False -> path
  }
}

pub fn summary(report: ImportReport) -> String {
  "imported examples="
  <> int.to_string(report.examples)
  <> " files="
  <> int.to_string(report.files)
  <> " source="
  <> report.source_root
  <> " out="
  <> report.out_root
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
