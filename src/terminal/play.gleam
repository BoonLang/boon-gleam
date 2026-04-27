import etch/command
import etch/event
import etch/stdout
import etch/terminal
import frontend/diagnostic.{type Diagnostic}
import gleam/erlang/process
import gleam/option.{None, Some}
import gleam/string
import terminal/arkanoid
import terminal/canvas
import terminal/pong

const frame_timeout_ms = 16

type FrameMessage {
  FrameMessage
}

pub fn play(example_path: String) -> Result(Nil, List(Diagnostic)) {
  terminal.enter_raw()
  event.init_event_server()
  stdout.execute([
    command.EnterAlternateScreen,
    command.HideCursor,
    command.DisableLineWrap,
    command.Clear(terminal.All),
  ])

  let result = case string.contains(example_path, "arkanoid") {
    True -> play_arkanoid(arkanoid.init())
    False -> play_pong(pong.init())
  }

  restore_terminal()
  Ok(result)
}

fn play_pong(state: pong.PongState) -> Nil {
  render(pong.score_text(state), pong.snapshot(state) |> canvas.to_text)

  case poll_key() {
    Quit -> Nil
    MoveUp -> play_pong(pong.tick(pong.move_left_paddle(state, -1)))
    MoveDown -> play_pong(pong.tick(pong.move_left_paddle(state, 1)))
    MoveLeft -> play_pong(pong.tick(pong.move_right_paddle(state, -1)))
    MoveRight -> play_pong(pong.tick(pong.move_right_paddle(state, 1)))
    NoInput -> play_pong(pong.tick(state))
  }
}

fn play_arkanoid(state: arkanoid.ArkanoidState) -> Nil {
  render(arkanoid.score_text(state), arkanoid.snapshot(state) |> canvas.to_text)

  case poll_key() {
    Quit -> Nil
    MoveLeft -> play_arkanoid(arkanoid.tick(arkanoid.move_paddle(state, -1)))
    MoveRight -> play_arkanoid(arkanoid.tick(arkanoid.move_paddle(state, 1)))
    MoveUp | MoveDown | NoInput -> play_arkanoid(arkanoid.tick(state))
  }
}

fn render(title: String, frame: String) -> Nil {
  stdout.execute([
    command.MoveTo(1, 1),
    command.Clear(terminal.All),
    command.Print(title <> "  q: quit\n" <> frame),
  ])
}

fn restore_terminal() -> Nil {
  stdout.execute([
    command.EnableLineWrap,
    command.ShowCursor,
    command.LeaveAlternateScreen,
  ])
  terminal.exit_raw()
}

type DirectInput {
  Quit
  MoveUp
  MoveDown
  MoveLeft
  MoveRight
  NoInput
}

fn poll_key() -> DirectInput {
  let input = case event.poll(0) {
    Some(Ok(event.Key(key))) -> key_to_input(key)
    Some(Ok(_)) | Some(Error(_)) | None -> NoInput
  }
  case input {
    Quit -> Quit
    _ -> {
      wait_frame()
      input
    }
  }
}

fn wait_frame() -> Nil {
  let subject = process.new_subject()
  case process.receive(subject, within: frame_timeout_ms) {
    Ok(FrameMessage) -> Nil
    Error(_) -> Nil
  }
}

fn key_to_input(key: event.KeyEvent) -> DirectInput {
  case key.code {
    event.Esc -> Quit
    event.Char("q") -> Quit
    event.Char("Q") -> Quit
    event.Char("c") if key.modifiers.control -> Quit
    event.Char("C") if key.modifiers.control -> Quit
    event.Char("\u{0003}") -> Quit
    event.Char("w") | event.Char("W") | event.UpArrow -> MoveUp
    event.Char("s") | event.Char("S") | event.DownArrow -> MoveDown
    event.Char("a") | event.Char("A") | event.LeftArrow -> MoveLeft
    event.Char("d") | event.Char("D") | event.RightArrow -> MoveRight
    _ -> NoInput
  }
}
