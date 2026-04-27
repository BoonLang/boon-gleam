import gleam/erlang/atom
import gleam/erlang/charlist.{type Charlist}
import gleam/int

@external(erlang, "erlang", "halt")
pub fn exit(code: Int) -> Nil

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: atom.Atom) -> Int

pub fn monotonic_microsecond() -> Int {
  monotonic_time(atom.create("microsecond"))
}

@external(erlang, "erlang", "system_info")
fn system_info_charlist(name: atom.Atom) -> Charlist

@external(erlang, "erlang", "system_info")
fn system_info_int(name: atom.Atom) -> Int

pub fn otp_release() -> String {
  system_info_charlist(atom.create("otp_release"))
  |> charlist.to_string
}

pub fn runtime_summary() -> String {
  "otp="
  <> otp_release()
  <> " schedulers="
  <> int.to_string(system_info_int(atom.create("schedulers_online")))
  <> " wordsize="
  <> int.to_string(system_info_int(atom.create("wordsize")))
  <> " process_count="
  <> int.to_string(system_info_int(atom.create("process_count")))
}
