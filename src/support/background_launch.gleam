import gleam/erlang/charlist.{type Charlist}
import gleam/int
import gleam/string
import support/file

@external(erlang, "os", "cmd")
fn os_cmd(command: Charlist) -> Charlist

pub fn available() -> Bool {
  command_succeeds(
    "command -v cosmic-background-launch >/dev/null && busctl --user list | grep -q 'com.system76.CosmicComp.BackgroundLaunch'",
  )
}

pub fn run_and_wait(
  label: String,
  command: String,
  timeout_seconds: Int,
) -> Bool {
  let dir = "build/cache/background-launch"
  let script_path = dir <> "/" <> label <> ".sh"
  let status_path = dir <> "/" <> label <> ".status"
  let output_path = dir <> "/" <> label <> ".out"
  let script =
    "#!/bin/sh\n"
    <> "set +e\n"
    <> command
    <> "\n"
    <> "status=$?\n"
    <> "echo \"$status\" > "
    <> shell_quote(status_path)
    <> "\n"
    <> "exit \"$status\"\n"
  case file.write_text_file(script_path, script) {
    Error(_) -> False
    Ok(_) -> {
      let launcher =
        "rm -f "
        <> shell_quote(status_path)
        <> " "
        <> shell_quote(output_path)
        <> "; chmod +x "
        <> shell_quote(script_path)
        <> "; cosmic-background-launch --workspace codex -- sh "
        <> shell_quote(script_path)
        <> " > "
        <> shell_quote(output_path)
        <> " 2>&1"
        <> "; i=0; while [ \"$i\" -lt "
        <> int.to_string(timeout_seconds)
        <> " ]; do if [ -f "
        <> shell_quote(status_path)
        <> " ]; then test \"$(cat "
        <> shell_quote(status_path)
        <> ")\" = \"0\"; result=$?; echo EXIT:$result; exit $result; fi; sleep 1; i=$((i + 1)); done; echo EXIT:124; exit 124"
      command_succeeds(launcher)
    }
  }
}

fn command_succeeds(command: String) -> Bool {
  os_cmd(charlist.from_string(
    "sh -c " <> shell_quote(command <> "; echo EXIT:$?"),
  ))
  |> charlist.to_string
  |> string.contains("EXIT:0")
}

fn shell_quote(value: String) -> String {
  "'" <> string.replace(value, "'", "'\"'\"'") <> "'"
}
