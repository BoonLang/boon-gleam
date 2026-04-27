# boon-gleam

`boon-gleam` is a Gleam implementation and codegen backend for Boon.

The canonical implementation contract is
[`BOON_GLEAM_IMPLEMENTATION_PLAN.md`](./BOON_GLEAM_IMPLEMENTATION_PLAN.md).
Work proceeds phase by phase from that file. The current implementation covers
the Phase 0 through Phase 11 acceptance surface plus the performance report
commands described by the plan.

## Development

Required preflight:

```sh
gleam --version
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
```

Basic checks:

```sh
gleam test
gleam run -- help
gleam run -- verify-all
```

Long-running commands such as `play` and `serve` have bounded counterparts for
automation: `play-smoke`, `serve-smoke`, `verify-backend`, and
`verify-durability`.
