import gleam/int
import gleam/list
import gleam/string
import support/hash
import terminal/canvas.{type Canvas}

pub type PongState {
  PongState(
    width: Int,
    height: Int,
    ball_x: Int,
    ball_y: Int,
    vx: Int,
    vy: Int,
    left_y: Int,
    right_y: Int,
    left_score: Int,
    right_score: Int,
  )
}

pub fn init() -> PongState {
  PongState(
    width: 40,
    height: 12,
    ball_x: 20,
    ball_y: 6,
    vx: 1,
    vy: 1,
    left_y: 5,
    right_y: 5,
    left_score: 0,
    right_score: 0,
  )
}

pub fn run_ticks(ticks: Int) -> PongState {
  tick_loop(init(), ticks)
}

pub fn snapshot(state: PongState) -> Canvas {
  let rows = build_rows(state, 0, [])
  canvas.from_lines(rows)
}

pub fn snapshot_hash(state: PongState) -> String {
  state
  |> snapshot
  |> canvas.to_text
  |> hash.sha256_hex
}

pub fn score_text(state: PongState) -> String {
  "PONG "
  <> int.to_string(state.left_score)
  <> ":"
  <> int.to_string(state.right_score)
}

fn tick_loop(state: PongState, remaining: Int) -> PongState {
  case remaining <= 0 {
    True -> state
    False -> tick_loop(tick(state), remaining - 1)
  }
}

pub fn tick(state: PongState) -> PongState {
  let next_x = state.ball_x + state.vx
  let next_y = state.ball_y + state.vy
  let bounced_vy = case next_y <= 1 || next_y >= state.height - 2 {
    True -> 0 - state.vy
    False -> state.vy
  }
  let y = clamp(next_y, 1, state.height - 2)
  let left_hit = next_x == 2 && within_paddle(y, state.left_y)
  let right_hit = next_x == state.width - 3 && within_paddle(y, state.right_y)
  let bounced_vx = case left_hit || right_hit {
    True -> 0 - state.vx
    False -> state.vx
  }

  case next_x <= 0 {
    True ->
      PongState(
        ..state,
        ball_x: state.width / 2,
        ball_y: state.height / 2,
        vx: 1,
        vy: bounced_vy,
        right_score: state.right_score + 1,
      )
    False ->
      case next_x >= state.width - 1 {
        True ->
          PongState(
            ..state,
            ball_x: state.width / 2,
            ball_y: state.height / 2,
            vx: -1,
            vy: bounced_vy,
            left_score: state.left_score + 1,
          )
        False ->
          PongState(
            ..state,
            ball_x: next_x,
            ball_y: y,
            vx: bounced_vx,
            vy: bounced_vy,
          )
      }
  }
}

pub fn move_left_paddle(state: PongState, delta: Int) -> PongState {
  PongState(..state, left_y: clamp(state.left_y + delta, 2, state.height - 3))
}

pub fn move_right_paddle(state: PongState, delta: Int) -> PongState {
  PongState(..state, right_y: clamp(state.right_y + delta, 2, state.height - 3))
}

fn within_paddle(y: Int, paddle_y: Int) -> Bool {
  y >= paddle_y - 1 && y <= paddle_y + 1
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

fn build_rows(state: PongState, row: Int, acc: List(String)) -> List(String) {
  case row >= state.height {
    True -> list.reverse(acc)
    False -> build_rows(state, row + 1, [build_row(state, row, 0, []), ..acc])
  }
}

fn build_row(
  state: PongState,
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

fn cell_at(state: PongState, row: Int, column: Int) -> String {
  case row == 0 || row == state.height - 1 {
    True -> "#"
    False ->
      case column == 0 || column == state.width - 1 {
        True -> "#"
        False ->
          case column == state.ball_x && row == state.ball_y {
            True -> "o"
            False ->
              case is_paddle(state, row, column) {
                True -> "|"
                False -> " "
              }
          }
      }
  }
}

fn is_paddle(state: PongState, row: Int, column: Int) -> Bool {
  { column == 1 && within_paddle(row, state.left_y) }
  || { column == state.width - 2 && within_paddle(row, state.right_y) }
}
