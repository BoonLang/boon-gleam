@external(erlang, "boongleam_ffi", "exit")
pub fn exit(code: Int) -> Nil

@external(erlang, "boongleam_ffi", "monotonic_microsecond")
pub fn monotonic_microsecond() -> Int

@external(erlang, "boongleam_ffi", "otp_release")
pub fn otp_release() -> String

@external(erlang, "boongleam_ffi", "runtime_summary")
pub fn runtime_summary() -> String
