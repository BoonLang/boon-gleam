import gleam/erlang/charlist.{type Charlist}
import gleam/list

@external(erlang, "init", "get_plain_arguments")
fn erlang_start_arguments() -> List(Charlist)

pub fn start_arguments() -> List(String) {
  erlang_start_arguments()
  |> list.map(charlist.to_string)
}
