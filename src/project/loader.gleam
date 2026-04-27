import frontend/ast.{type Program}
import frontend/diagnostic.{type Diagnostic, error}
import frontend/lexer
import frontend/parser
import frontend/source_file.{SourceFile}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import project/project.{
  type BuildReport, type Project, type ProjectFile, BuildReport, Project,
  ProjectFile,
}
import support/file

pub fn load(path: String) -> Result(Project, List(Diagnostic)) {
  case file.is_directory(path) {
    True -> load_directory(path)
    False -> load_single_file(path)
  }
}

pub fn parse_project(project: Project) -> Result(Program, List(Diagnostic)) {
  let source = project.entry_file
  use tokens <- result_try(lexer.lex(source.path, source.contents))
  parser.parse(source.path, tokens)
}

fn load_single_file(path: String) -> Result(Project, List(Diagnostic)) {
  case file.read_text_file(path) {
    Ok(contents) ->
      Ok(Project(
        name: example_name(path),
        root: parent_directory(path),
        entry_file: SourceFile(path: path, contents: contents),
        files: [SourceFile(path: path, contents: contents)],
        project_files: [
          ProjectFile(
            path: file_name(path),
            contents: contents,
            generated: False,
          ),
        ],
        assets_root: None,
        build_report: None,
      ))
    Error(message) ->
      Error([
        error(
          code: "source_read_failed",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "check the example path and imported corpus files",
        ),
      ])
  }
}

fn load_directory(path: String) -> Result(Project, List(Diagnostic)) {
  let root = trim_trailing_slash(path)
  let has_build_file = has_file(root <> "/BUILD.bn")
  let entry_path = case has_build_file {
    True -> root <> "/RUN.bn"
    False -> root <> "/" <> example_name(root) <> ".bn"
  }

  use build_report <- result_try(execute_build(root, has_build_file))
  use project_files <- result_try(load_project_files(root))
  use entry_contents <- result_try(read_required_file(entry_path))

  let source_files =
    project_files
    |> list.filter(fn(project_file) { project_file.path != "BUILD.bn" })
    |> list.map(fn(project_file) {
      SourceFile(
        path: root <> "/" <> project_file.path,
        contents: project_file.contents,
      )
    })

  Ok(Project(
    name: example_name(root),
    root: root,
    entry_file: SourceFile(path: entry_path, contents: entry_contents),
    files: source_files,
    project_files: project_files,
    assets_root: assets_root(root),
    build_report: build_report,
  ))
}

fn load_project_files(
  root: String,
) -> Result(List(ProjectFile), List(Diagnostic)) {
  case file.list_files_recursive(root) {
    Ok(paths) -> {
      let boon_paths =
        paths
        |> list.filter(fn(path) { string.ends_with(path, ".bn") })
        |> list.sort(string.compare)

      list.try_map(boon_paths, fn(path) {
        case file.read_text_file(path) {
          Ok(contents) -> {
            let relative_path = relative_to(root, path)
            Ok(ProjectFile(
              path: relative_path,
              contents: contents,
              generated: is_generated_file(relative_path),
            ))
          }
          Error(message) ->
            Error([
              error(
                code: "source_read_failed",
                path: path,
                line: 1,
                column: 1,
                span_start: 0,
                span_end: 0,
                message: message,
                help: "check the example path and imported corpus files",
              ),
            ])
        }
      })
    }
    Error(message) ->
      Error([
        error(
          code: "project_read_failed",
          path: root,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "project directories must be readable virtual file systems",
        ),
      ])
  }
}

fn read_required_file(path: String) -> Result(String, List(Diagnostic)) {
  case file.read_text_file(path) {
    Ok(contents) -> Ok(contents)
    Error(message) ->
      Error([
        error(
          code: "source_read_failed",
          path: path,
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "check the example path and imported corpus files",
        ),
      ])
  }
}

fn execute_build(
  root: String,
  has_build_file: Bool,
) -> Result(Option(BuildReport), List(Diagnostic)) {
  case has_build_file {
    False -> Ok(None)
    True -> {
      use build_source <- result_try(read_required_file(root <> "/BUILD.bn"))
      use _ <- result_try(validate_build_contract(root, build_source))
      let icon_inputs = icon_input_files(root)
      use _ <- result_try(generate_assets(root, icon_inputs))
      Ok(
        Some(
          BuildReport(
            path: "BUILD.bn",
            generated_files: ["Generated/Assets.bn"],
            input_files: icon_inputs,
            succeeded: True,
            messages: [
              "Included " <> int_string(list.length(icon_inputs)) <> " icons",
            ],
          ),
        ),
      )
    }
  }
}

fn validate_build_contract(
  root: String,
  build_source: String,
) -> Result(Nil, List(Diagnostic)) {
  case
    string.contains(build_source, "Directory/entries()")
    && string.contains(build_source, "File/write_text(path: output_file)")
    && string.contains(build_source, "Build/succeed()")
    && string.contains(build_source, "./assets/icons")
    && string.contains(build_source, "./Generated/Assets.bn")
    && !string.contains(build_source, "../")
    && !string.contains(build_source, " /")
  {
    True -> Ok(Nil)
    False ->
      Error([
        error(
          code: "unsupported_build_contract",
          path: root <> "/BUILD.bn",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: "BUILD.bn does not match the supported sandboxed asset generation contract",
          help: "Phase 11 BUILD.bn may read ./assets/icons and write ./Generated/Assets.bn only",
        ),
      ])
  }
}

fn generate_assets(
  root: String,
  icon_inputs: List(String),
) -> Result(Nil, List(Diagnostic)) {
  case
    file.write_text_file(
      root <> "/Generated/Assets.bn",
      generated_assets_source(root, icon_inputs),
    )
  {
    Ok(_) -> Ok(Nil)
    Error(message) ->
      Error([
        error(
          code: "build_write_failed",
          path: root <> "/BUILD.bn",
          line: 1,
          column: 1,
          span_start: 0,
          span_end: 0,
          message: message,
          help: "BUILD.bn may only write generated files under the project root",
        ),
      ])
  }
}

fn generated_assets_source(root: String, icon_inputs: List(String)) -> String {
  "-- GENERATED CODE - DO NOT EDIT\n"
  <> "-- Generated by BUILD.bn from assets/icons/\n"
  <> "-- Generated at: 2025-01-01T00:00:00Z\n\n"
  <> "FUNCTION icon() {\n"
  <> "    [\n"
  <> string.join(
    list.map(icon_inputs, fn(path) { icon_entry(root, path) }),
    with: "\n\n",
  )
  <> "\n"
  <> "    ]\n"
  <> "}\n"
}

fn icon_entry(root: String, path: String) -> String {
  let contents = case file.read_text_file(root <> "/" <> path) {
    Ok(contents) -> contents
    Error(_) -> ""
  }
  "        "
  <> file_stem(path)
  <> ": TEXT {\n"
  <> "            data:image/svg+xml;utf8,"
  <> url_encode_svg(string.trim(contents))
  <> "\n"
  <> "        }"
}

fn icon_input_files(root: String) -> List(String) {
  case file.list_files_recursive(root <> "/assets/icons") {
    Ok(paths) ->
      paths
      |> list.filter(fn(path) { string.ends_with(path, ".svg") })
      |> list.map(fn(path) { relative_to(root, path) })
      |> list.sort(string.compare)
    Error(_) -> []
  }
}

fn file_stem(path: String) -> String {
  let name = file_name(path)
  case string.ends_with(name, ".svg") {
    True -> string.drop_end(name, up_to: 4)
    False -> name
  }
}

fn url_encode_svg(contents: String) -> String {
  contents
  |> string.replace(each: "%", with: "%25")
  |> string.replace(each: "<", with: "%3C")
  |> string.replace(each: ">", with: "%3E")
  |> string.replace(each: "\"", with: "%22")
  |> string.replace(each: "#", with: "%23")
  |> string.replace(each: " ", with: "%20")
}

fn assets_root(root: String) -> Option(String) {
  case file.is_directory(root <> "/assets") {
    True -> Some("assets")
    False -> None
  }
}

fn has_file(path: String) -> Bool {
  case file.read_text_file(path) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn is_generated_file(path: String) -> Bool {
  string.starts_with(path, "Generated/")
}

fn relative_to(root: String, path: String) -> String {
  let prefix = root <> "/"
  case string.starts_with(path, prefix) {
    True -> string.drop_start(path, up_to: string.length(prefix))
    False -> path
  }
}

fn example_name(path: String) -> String {
  path
  |> string.split(on: "/")
  |> list.filter(fn(part) { !string.is_empty(part) })
  |> list.last
  |> result.unwrap(path)
}

fn parent_directory(path: String) -> String {
  path
  |> string.split(on: "/")
  |> drop_last
  |> string.join(with: "/")
}

fn file_name(path: String) -> String {
  path
  |> string.split(on: "/")
  |> list.last
  |> result.unwrap(path)
}

fn drop_last(parts: List(String)) -> List(String) {
  parts
  |> list.reverse
  |> list.drop(1)
  |> list.reverse
}

fn trim_trailing_slash(path: String) -> String {
  case string.ends_with(path, "/") {
    True -> string.drop_end(path, up_to: 1)
    False -> path
  }
}

fn int_string(value: Int) -> String {
  value
  |> int.to_string
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
