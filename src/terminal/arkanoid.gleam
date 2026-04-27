import gleam/int
import gleam/list
import gleam/string
import support/hash
import terminal/canvas.{type Canvas}

pub type ArkanoidState {
  ArkanoidState(
    width: Int,
    height: Int,
    ball_x: Int,
    ball_y: Int,
    vx: Int,
    vy: Int,
    paddle_x: Int,
    bricks_left: Int,
    score: Int,
  )
}

pub fn init() -> ArkanoidState {
  ArkanoidState(
    width: 40,
    height: 16,
    ball_x: 20,
    ball_y: 12,
    vx: 1,
    vy: -1,
    paddle_x: 20,
    bricks_left: 24,
    score: 0,
  )
}

pub fn run_ticks(ticks: Int) -> ArkanoidState {
  tick_loop(init(), ticks)
}

pub fn snapshot(state: ArkanoidState) -> Canvas {
  canvas.from_lines(build_rows(state, 0, []))
}

pub fn snapshot_hash(state: ArkanoidState) -> String {
  state
  |> snapshot
  |> canvas.to_text
  |> hash.sha256_hex
}

pub fn score_text(state: ArkanoidState) -> String {
  "ARKANOID score " <> int.to_string(state.score)
}

fn tick_loop(state: ArkanoidState, remaining: Int) -> ArkanoidState {
  case remaining <= 0 {
    True -> state
    False -> tick_loop(tick(state), remaining - 1)
  }
}

pub fn tick(state: ArkanoidState) -> ArkanoidState {
  let next_x = state.ball_x + state.vx
  let next_y = state.ball_y + state.vy
  let hit_side = next_x <= 1 || next_x >= state.width - 2
  let hit_top_or_brick = next_y <= 3
  let hit_paddle =
    next_y >= state.height - 3
    && next_x >= state.paddle_x - 3
    && next_x <= state.paddle_x + 3
  let vx = case hit_side {
    True -> 0 - state.vx
    False -> state.vx
  }
  let vy = case hit_top_or_brick || hit_paddle {
    True -> 0 - state.vy
    False -> state.vy
  }
  let scored = hit_top_or_brick && state.bricks_left > 0
  ArkanoidState(
    ..state,
    ball_x: clamp(next_x, 1, state.width - 2),
    ball_y: clamp(next_y, 1, state.height - 2),
    vx: vx,
    vy: vy,
    bricks_left: case scored {
      True -> state.bricks_left - 1
      False -> state.bricks_left
    },
    score: case scored {
      True -> state.score + 10
      False -> state.score
    },
  )
}

pub fn move_paddle(state: ArkanoidState, delta: Int) -> ArkanoidState {
  ArkanoidState(
    ..state,
    paddle_x: clamp(state.paddle_x + delta, 4, state.width - 5),
  )
}

fn clamp(value: Int, minimum: Int, maximum: Int) -> Int {
  case value < minimum {
    True -> minimum
    False ->
      case value > maximum {
        True -> maximum
        False -> value
      }
  }
}

fn build_rows(
  state: ArkanoidState,
  row: Int,
  acc: List(String),
) -> List(String) {
  case row >= state.height {
    True -> list.reverse(acc)
    False -> build_rows(state, row + 1, [build_row(state, row, 0, []), ..acc])
  }
}

fn build_row(
  state: ArkanoidState,
  row: Int,
  column: Int,
  acc: List(String),
) -> String {
  case column >= state.width {
    True -> acc |> list.reverse |> string.join(with: "")
    False ->
      build_row(state, row, column + 1, [cell_at(state, row, column), ..acc])
  }
}

fn cell_at(state: ArkanoidState, row: Int, column: Int) -> String {
  case
    row == 0
    || row == state.height - 1
    || column == 0
    || column == state.width - 1
  {
    True -> "#"
    False ->
      case row >= 2 && row <= 3 && brick_visible(state, row, column) {
        True -> "="
        False ->
          case row == state.ball_y && column == state.ball_x {
            True -> "o"
            False ->
              case
                row == state.height - 2
                && column >= state.paddle_x - 3
                && column <= state.paddle_x + 3
              {
                True -> "_"
                False -> " "
              }
          }
      }
  }
}

fn brick_visible(state: ArkanoidState, row: Int, column: Int) -> Bool {
  let brick_index = { row - 2 } * 12 + { column - 2 } / 3
  column >= 2 && column < 38 && brick_index < state.bricks_left
}
