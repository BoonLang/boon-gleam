import gleam/bit_array
import gleam/string

type HashAlgorithm {
  Sha256
}

@external(erlang, "crypto", "hash")
fn crypto_hash(algorithm: HashAlgorithm, contents: BitArray) -> BitArray

pub fn sha256_hex(contents: String) -> String {
  crypto_hash(Sha256, bit_array.from_string(contents))
  |> bit_array.base16_encode
  |> string.lowercase
}
