@external(erlang, "boongleam_ffi", "read_text_file")
pub fn read_text_file(path: String) -> Result(String, String)

@external(erlang, "boongleam_ffi", "write_text_file")
pub fn write_text_file(path: String, contents: String) -> Result(Nil, String)

@external(erlang, "boongleam_ffi", "copy_file")
pub fn copy_file(source: String, destination: String) -> Result(Nil, String)

@external(erlang, "boongleam_ffi", "make_dir_all")
pub fn make_dir_all(path: String) -> Result(Nil, String)

@external(erlang, "boongleam_ffi", "is_directory")
pub fn is_directory(path: String) -> Bool

@external(erlang, "boongleam_ffi", "list_files_recursive")
pub fn list_files_recursive(path: String) -> Result(List(String), String)
