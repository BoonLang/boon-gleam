import runtime/core.{
  type Effect, type Event, type InitContext, type Snapshot, type State,
}

pub type AppCore {
  AppCore(
    init: fn(InitContext) -> State,
    update: fn(State, Event) -> #(State, List(Effect)),
    view: fn(State) -> Snapshot,
  )
}

pub type BoonGleamRuntimeHost {
  BoonGleamRuntimeHost(core: AppCore)
}

pub fn init(host: BoonGleamRuntimeHost, context: InitContext) -> State {
  host.core.init(context)
}

pub fn update(
  host: BoonGleamRuntimeHost,
  state: State,
  event: Event,
) -> #(State, List(Effect)) {
  host.core.update(state, event)
}

pub fn view(host: BoonGleamRuntimeHost, state: State) -> Snapshot {
  host.core.view(state)
}
