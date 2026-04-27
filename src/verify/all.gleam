import frontend/diagnostic.{type Diagnostic}
import gleam/list
import terminal/verify as terminal_verify
import verify/runner

pub type VerifyAllReport {
  VerifyAllReport(semantic_count: Int, terminal_count: Int)
}

pub fn run() -> Result(VerifyAllReport, List(Diagnostic)) {
  let semantic_examples = [
    "examples/upstream/minimal",
    "examples/upstream/hello_world",
    "examples/upstream/counter",
    "examples/upstream/counter_hold",
    "examples/upstream/complex_counter",
    "examples/upstream/shopping_list",
    "examples/upstream/todo_mvc",
    "examples/upstream/todo_mvc_physical",
  ]
  let terminal_examples = [
    "examples/terminal/pong",
    "examples/terminal/arkanoid",
  ]

  use _semantic <- result_try(list.try_map(semantic_examples, runner.verify))
  use _terminal <- result_try(list.try_map(
    terminal_examples,
    terminal_verify.verify,
  ))

  Ok(VerifyAllReport(
    semantic_count: list.length(semantic_examples),
    terminal_count: list.length(terminal_examples),
  ))
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
