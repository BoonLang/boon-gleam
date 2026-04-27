import gleam/string

pub type Canvas {
  Canvas(width: Int, height: Int, cells: List(String))
}

pub fn from_lines(lines: List(String)) -> Canvas {
  Canvas(width: line_width(lines), height: list_length(lines, 0), cells: lines)
}

pub fn to_text(canvas: Canvas) -> String {
  string.join(canvas.cells, with: "\n")
}

fn line_width(lines: List(String)) -> Int {
  case lines {
    [] -> 0
    [line, ..] -> string.length(line)
  }
}

fn list_length(items: List(a), count: Int) -> Int {
  case items {
    [] -> count
    [_, ..rest] -> list_length(rest, count + 1)
  }
}
