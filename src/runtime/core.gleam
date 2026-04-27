pub type InitContext {
  InitContext(seed: Int)
}

pub type SemanticNode {
  SemanticNode(id: String, path: String, text: String)
}

pub type Snapshot {
  Snapshot(text: String, semantic_nodes: List(SemanticNode))
}

pub type TodoItem {
  TodoItem(title: String, completed: Bool)
}

pub type State {
  State(
    count: Int,
    input: String,
    items: List(String),
    todos: List(TodoItem),
    filter: String,
    editing: String,
    theme: String,
    dark: Bool,
    view_style: String,
    snapshot: Snapshot,
  )
}

pub type Event {
  NoEvent
  ClickButton(index: Int)
  ClickButtonNearText(text: String, label: String)
  ClickCheckbox(index: Int)
  ClickCheckboxNearText(text: String)
  ChangeText(link_id: String, text: String)
  ClickText(text: String)
  DblClickText(text: String)
  KeyDown(link_id: String, key: String)
}

pub type Effect {
  NoEffect
}
