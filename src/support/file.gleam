import gleam/bit_array
import gleam/erlang/atom
import gleam/erlang/charlist.{type Charlist}
import gleam/list
import gleam/string

@external(erlang, "file", "read_file")
fn erlang_read_file(path: Charlist) -> Result(BitArray, atom.Atom)

@external(erlang, "file", "write_file")
fn erlang_write_file(path: Charlist, contents: String) -> atom.Atom

@external(erlang, "file", "copy")
fn erlang_copy_file(
  source: Charlist,
  destination: Charlist,
) -> Result(Int, atom.Atom)

@external(erlang, "file", "list_dir")
fn erlang_list_dir(path: Charlist) -> Result(List(Charlist), atom.Atom)

@external(erlang, "filelib", "ensure_dir")
fn erlang_ensure_dir(path: Charlist) -> atom.Atom

@external(erlang, "filelib", "is_dir")
fn erlang_is_dir(path: Charlist) -> Bool

pub fn read_text_file(path: String) -> Result(String, String) {
  case erlang_read_file(charlist.from_string(path)) {
    Ok(contents) ->
      contents
      |> bit_array.to_string
      |> result_map_error(fn(_) { "file is not valid utf-8: " <> path })
    Error(reason) -> Error(atom.to_string(reason))
  }
}

pub fn write_text_file(path: String, contents: String) -> Result(Nil, String) {
  case make_parent_dir(path) {
    Error(reason) -> Error(reason)
    Ok(_) ->
      atom_result(erlang_write_file(charlist.from_string(path), contents))
  }
}

pub fn copy_file(source: String, destination: String) -> Result(Nil, String) {
  case make_parent_dir(destination) {
    Error(reason) -> Error(reason)
    Ok(_) ->
      case
        erlang_copy_file(
          charlist.from_string(source),
          charlist.from_string(destination),
        )
      {
        Ok(_) -> Ok(Nil)
        Error(reason) -> Error(atom.to_string(reason))
      }
  }
}

pub fn make_dir_all(path: String) -> Result(Nil, String) {
  atom_result(erlang_ensure_dir(charlist.from_string(path <> "/.keep")))
}

pub fn is_directory(path: String) -> Bool {
  erlang_is_dir(charlist.from_string(path))
}

pub fn list_files_recursive(path: String) -> Result(List(String), String) {
  case is_directory(path) {
    False -> Error("directory does not exist")
    True -> {
      let files = list_files_recursive_loop(path, [])
      Ok(list.sort(files, string.compare))
    }
  }
}

fn list_files_recursive_loop(
  directory: String,
  accumulator: List(String),
) -> List(String) {
  case erlang_list_dir(charlist.from_string(directory)) {
    Error(_) -> accumulator
    Ok(entries) ->
      list.fold(entries, accumulator, fn(acc, entry) {
        let name = charlist.to_string(entry)
        let path = directory <> "/" <> name
        case is_directory(path) {
          True -> list_files_recursive_loop(path, acc)
          False -> [path, ..acc]
        }
      })
  }
}

fn make_parent_dir(path: String) -> Result(Nil, String) {
  atom_result(erlang_ensure_dir(charlist.from_string(path)))
}

fn atom_result(result: atom.Atom) -> Result(Nil, String) {
  case atom.to_string(result) {
    "ok" -> Ok(Nil)
    reason -> Error(reason)
  }
}

fn result_map_error(
  result: Result(a, e),
  with transform: fn(e) -> f,
) -> Result(a, f) {
  case result {
    Ok(value) -> Ok(value)
    Error(reason) -> Error(transform(reason))
  }
}
