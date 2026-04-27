import gleam/bit_array
import gleam/bytes_tree
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/charlist.{type Charlist}
import gleam/int
import gleam/list
import gleam/string

type Socket

@external(erlang, "application", "ensure_all_started")
fn ensure_all_started(application: atom.Atom) -> Dynamic

@external(erlang, "gleam_stdlib", "identity")
fn dynamic(a: a) -> Dynamic

@external(erlang, "httpc", "request")
fn httpc_request(
  method: atom.Atom,
  request: Dynamic,
  http_options: List(#(atom.Atom, Int)),
  options: List(#(atom.Atom, atom.Atom)),
) -> Result(#(#(String, Int, String), List(Dynamic), BitArray), Dynamic)

@external(erlang, "gen_tcp", "connect")
fn tcp_connect(
  host: Charlist,
  port: Int,
  options: List(Dynamic),
  timeout: Int,
) -> Result(Socket, Dynamic)

@external(erlang, "gen_tcp", "send")
fn tcp_send(socket: Socket, data: bytes_tree.BytesTree) -> atom.Atom

@external(erlang, "gen_tcp", "recv")
fn tcp_receive_timeout(
  socket: Socket,
  length: Int,
  timeout: Int,
) -> Result(BitArray, Dynamic)

@external(erlang, "gen_tcp", "close")
fn tcp_close(socket: Socket) -> Nil

@external(erlang, "crypto", "strong_rand_bytes")
fn strong_rand_bytes(size: Int) -> BitArray

pub fn request(
  method: String,
  url: String,
  body: String,
) -> Result(#(Int, String), String) {
  let _ = ensure_all_started(atom.create("inets"))
  let method_atom = atom.create(string.lowercase(method))
  let request = case string.uppercase(method) {
    "POST" ->
      dynamic(#(
        charlist.from_string(url),
        [],
        charlist.from_string("application/json"),
        body,
      ))
    _ -> dynamic(#(charlist.from_string(url), []))
  }
  case
    httpc_request(method_atom, request, [#(atom.create("timeout"), 5000)], [
      #(atom.create("body_format"), atom.create("binary")),
    ])
  {
    Ok(#(#(_, status, _), _, response_body)) ->
      case bit_array.to_string(response_body) {
        Ok(text) -> Ok(#(status, text))
        Error(_) -> Error("HTTP response was not utf-8")
      }
    Error(reason) -> Error(dynamic.classify(reason))
  }
}

pub fn websocket_smoke(
  host: String,
  port: Int,
  path: String,
  messages: List(String),
) -> Result(List(String), String) {
  let socket_options = [
    atom.to_dynamic(atom.create("binary")),
    dynamic(#(atom.create("active"), False)),
    dynamic(#(atom.create("packet"), atom.create("raw"))),
  ]
  case tcp_connect(charlist.from_string(host), port, socket_options, 5000) {
    Error(reason) -> Error(socket_reason(reason))
    Ok(socket) -> {
      let result = websocket_smoke_connected(socket, host, port, path, messages)
      let _ = tcp_close(socket)
      result
    }
  }
}

fn websocket_smoke_connected(
  socket: Socket,
  host: String,
  port: Int,
  path: String,
  messages: List(String),
) -> Result(List(String), String) {
  let key = websocket_client_key()
  let request =
    "GET "
    <> path
    <> " HTTP/1.1\r\nHost: "
    <> host
    <> ":"
    <> int.to_string(port)
    <> "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: "
    <> key
    <> "\r\nSec-WebSocket-Version: 13\r\n\r\n"
  use _ <- result_try_atom(tcp_send(socket, bytes_tree.from_string(request)))
  use _ <- result_try(recv_upgrade(socket, <<>>))
  websocket_send_messages(socket, messages, [])
}

fn recv_upgrade(socket: Socket, accumulator: BitArray) -> Result(Nil, String) {
  case tcp_receive_timeout(socket, 0, 5000) {
    Error(reason) -> Error(socket_reason(reason))
    Ok(chunk) -> {
      let next = bit_array.append(accumulator, chunk)
      case bit_array.to_string(next) {
        Ok(text) ->
          case
            string.contains(text, "\r\n\r\n"),
            string.contains(text, " 101 ")
          {
            True, True -> Ok(Nil)
            True, False -> Error("websocket upgrade did not return 101")
            False, _ -> recv_upgrade(socket, next)
          }
        Error(_) -> recv_upgrade(socket, next)
      }
    }
  }
}

fn websocket_send_messages(
  socket: Socket,
  messages: List(String),
  accumulator: List(String),
) -> Result(List(String), String) {
  case messages {
    [] -> Ok(list.reverse(accumulator))
    [message, ..rest] -> {
      use _ <- result_try_atom(tcp_send(
        socket,
        encode_client_text_frame(message),
      ))
      use frames <- result_try(recv_text_frames(socket, []))
      websocket_send_messages(
        socket,
        rest,
        list.append(list.reverse(frames), accumulator),
      )
    }
  }
}

fn recv_text_frames(
  socket: Socket,
  accumulator: List(String),
) -> Result(List(String), String) {
  let timeout = case accumulator {
    [] -> 5000
    _ -> 50
  }
  case tcp_receive_timeout(socket, 0, timeout) {
    Error(reason) ->
      case accumulator {
        [] -> Error(socket_reason(reason))
        _ -> Ok(list.reverse(accumulator))
      }
    Ok(data) -> {
      use frames <- result_try(decode_server_frames(data, accumulator))
      recv_text_frames(socket, frames)
    }
  }
}

fn websocket_client_key() -> String {
  strong_rand_bytes(16)
  |> bit_array.base64_encode(True)
}

fn encode_client_text_frame(message: String) -> bytes_tree.BytesTree {
  let payload = bit_array.from_string(message)
  let mask = strong_rand_bytes(4)
  let masked_payload = mask_payload(payload, mask, 0, <<>>)
  let length = bit_array.byte_size(payload)
  let frame = case length {
    length if length < 126 -> <<
      0x81,
      int.bitwise_or(0x80, length),
      mask:bits,
      masked_payload:bits,
    >>
    length if length < 65_536 -> <<
      0x81,
      int.bitwise_or(0x80, 126),
      length:int-size(16),
      mask:bits,
      masked_payload:bits,
    >>
    length -> <<
      0x81,
      int.bitwise_or(0x80, 127),
      length:int-size(64),
      mask:bits,
      masked_payload:bits,
    >>
  }
  bytes_tree.from_bit_array(frame)
}

fn mask_payload(
  payload: BitArray,
  mask: BitArray,
  index: Int,
  accumulator: BitArray,
) -> BitArray {
  case payload {
    <<byte, rest:bits>> -> {
      let masked = int.bitwise_exclusive_or(byte, mask_byte(mask, index % 4))
      mask_payload(rest, mask, index + 1, <<accumulator:bits, masked>>)
    }
    <<>> -> accumulator
    _ -> accumulator
  }
}

fn mask_byte(mask: BitArray, index: Int) -> Int {
  let assert <<a, b, c, d>> = mask
  case index {
    0 -> a
    1 -> b
    2 -> c
    _ -> d
  }
}

fn decode_server_frames(
  data: BitArray,
  accumulator: List(String),
) -> Result(List(String), String) {
  case data {
    <<>> -> Ok(accumulator)
    <<first, length_byte, rest:bits>> -> {
      let opcode = int.bitwise_and(first, 0x0f)
      let length_code = int.bitwise_and(length_byte, 0x7f)
      let masked = int.bitwise_and(length_byte, 0x80) == 0x80
      use parsed <- result_try(parse_payload(length_code, masked, rest))
      let #(payload, remaining) = parsed
      case opcode {
        1 -> {
          let text = case bit_array.to_string(payload) {
            Ok(text) -> text
            Error(_) -> ""
          }
          decode_server_frames(remaining, [text, ..accumulator])
        }
        8 -> Ok(list.reverse(accumulator))
        _ -> decode_server_frames(remaining, accumulator)
      }
    }
    _ -> Error("invalid websocket frame")
  }
}

fn parse_payload(
  length_code: Int,
  masked: Bool,
  rest: BitArray,
) -> Result(#(BitArray, BitArray), String) {
  case length_code {
    126 ->
      case rest {
        <<length:int-size(16), payload_rest:bits>> ->
          parse_payload_with_length(length, masked, payload_rest)
        _ -> Error("incomplete websocket frame")
      }
    127 ->
      case rest {
        <<length:int-size(64), payload_rest:bits>> ->
          parse_payload_with_length(length, masked, payload_rest)
        _ -> Error("incomplete websocket frame")
      }
    length -> parse_payload_with_length(length, masked, rest)
  }
}

fn parse_payload_with_length(
  length: Int,
  masked: Bool,
  rest: BitArray,
) -> Result(#(BitArray, BitArray), String) {
  case masked, rest {
    True, <<mask:bytes-size(4), payload:bytes-size(length), remaining:bits>> ->
      Ok(#(mask_payload(payload, mask, 0, <<>>), remaining))
    False, <<payload:bytes-size(length), remaining:bits>> ->
      Ok(#(payload, remaining))
    _, _ -> Error("incomplete websocket frame")
  }
}

fn socket_reason(reason: Dynamic) -> String {
  dynamic.classify(reason)
}

fn result_try(
  result: Result(a, String),
  rest: fn(a) -> Result(b, String),
) -> Result(b, String) {
  case result {
    Ok(value) -> rest(value)
    Error(reason) -> Error(reason)
  }
}

fn result_try_atom(
  result: atom.Atom,
  rest: fn(Nil) -> Result(b, String),
) -> Result(b, String) {
  case atom.to_string(result) {
    "ok" -> rest(Nil)
    reason -> Error(reason)
  }
}
