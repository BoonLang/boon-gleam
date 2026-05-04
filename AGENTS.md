# Agent Notes

`BOON_GLEAM_IMPLEMENTATION_PLAN.md` is the canonical implementation contract for
this repo. Keep changes and verification aligned with that file.

## COSMIC Background GUI Launches

When launching manual GUI playgrounds, browsers, editors, or other windows from
Codex, prefer `cosmic-background-launch` so the new window is routed away from
the user’s active workspace and does not steal focus.
Use it for verifier and test helper windows too, not only manual commands.

Use the helper around the actual command that creates the window:

```sh
cosmic-background-launch --workspace codex -- gleam run -m boongleam -- browser --serve --example counter --port 8080
cosmic-background-launch --workspace codex -- firefox http://127.0.0.1:8080/
```

For native GUI commands, keep the wrapper as close as possible to the real
window-creating phase:

```sh
cosmic-background-launch --workspace codex -- gleam run -m boongleam -- gui --example counter
```

Verifier/test commands that create windows must also go through the helper. The
repo code should wrap the actual Firefox/native GUI process and then wait for a
status artifact from that launched process, because `cosmic-background-launch`
returns as soon as the background launch is registered.

Why this matters:

- It avoids interrupting the user while manual GUI checks are running.
- COSMIC routes the window by launch metadata inherited by the window process.
- Wrapping a long build/bootstrap command is less reliable if the actual GUI
  process starts much later from a child process.

Before relying on it, verify the compositor-side service exists:

```sh
busctl --user list | rg 'com\.system76\.CosmicComp\.BackgroundLaunch'
```

The installed helper currently reports this usage:

```sh
cosmic-background-launch --workspace <name> -- <command> [args...]
```
