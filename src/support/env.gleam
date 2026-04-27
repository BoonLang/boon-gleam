import gleam/erlang/charlist.{type Charlist}

const missing = "__BOON_GLEAM_ENV_NOT_SET__"

@external(erlang, "os", "getenv")
fn erlang_getenv(name: Charlist, default: Charlist) -> Charlist

pub fn get(name: String) -> Result(String, String) {
  let missing_charlist = charlist.from_string(missing)
  case erlang_getenv(charlist.from_string(name), missing_charlist) {
    value if value == missing_charlist ->
      Error("environment variable is not set")
    value -> Ok(charlist.to_string(value))
  }
}
