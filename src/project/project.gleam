import frontend/source_file.{type SourceFile}
import gleam/option.{type Option}

pub type ProjectFile {
  ProjectFile(path: String, contents: String, generated: Bool)
}

pub type BuildReport {
  BuildReport(
    path: String,
    generated_files: List(String),
    input_files: List(String),
    succeeded: Bool,
    messages: List(String),
  )
}

pub type Project {
  Project(
    name: String,
    root: String,
    entry_file: SourceFile,
    files: List(SourceFile),
    project_files: List(ProjectFile),
    assets_root: Option(String),
    build_report: Option(BuildReport),
  )
}
