@external(erlang, "boongleam_ffi", "http_request")
pub fn request(
  method: String,
  url: String,
  body: String,
) -> Result(#(Int, String), String)

@external(erlang, "boongleam_ffi", "websocket_smoke")
pub fn websocket_smoke(
  host: String,
  port: Int,
  path: String,
  messages: List(String),
) -> Result(List(String), String)
