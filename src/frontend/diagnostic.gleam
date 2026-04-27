import gleam/int

pub type Severity {
  SeverityError
  SeverityWarning
  SeverityInfo
}

pub type Diagnostic {
  Diagnostic(
    code: String,
    severity: Severity,
    path: String,
    line: Int,
    column: Int,
    span_start: Int,
    span_end: Int,
    message: String,
    help: String,
  )
}

pub fn error(
  code code: String,
  path path: String,
  line line: Int,
  column column: Int,
  span_start span_start: Int,
  span_end span_end: Int,
  message message: String,
  help help: String,
) -> Diagnostic {
  Diagnostic(
    code:,
    severity: SeverityError,
    path:,
    line:,
    column:,
    span_start:,
    span_end:,
    message:,
    help:,
  )
}

pub fn to_line(diagnostic: Diagnostic) -> String {
  let severity = case diagnostic.severity {
    SeverityError -> "error"
    SeverityWarning -> "warning"
    SeverityInfo -> "info"
  }

  diagnostic.path
  <> ":"
  <> int.to_string(diagnostic.line)
  <> ":"
  <> int.to_string(diagnostic.column)
  <> ": "
  <> severity
  <> "["
  <> diagnostic.code
  <> "]: "
  <> diagnostic.message
  <> case diagnostic.help == "" {
    True -> ""
    False -> "\n  help: " <> diagnostic.help
  }
}
