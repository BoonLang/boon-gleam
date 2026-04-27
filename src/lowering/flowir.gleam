import lowering/sourceshape.{type SourceShape}

pub type FlowProgram {
  FlowProgram(
    name: String,
    core: FlowCore,
    snapshot_text: String,
    source_shapes: List(SourceShape),
  )
}

pub type FlowCore {
  StaticText
  NumericText(buttons: List(FlowButton))
  ShoppingList(ShoppingListSpec)
  TodoList(TodoListSpec)
}

pub type FlowButton {
  FlowButton(label: String, delta: Int)
}

pub type ShoppingListSpec {
  ShoppingListSpec(
    input_link_id: String,
    clear_link_id: String,
    placeholder: String,
  )
}

pub type TodoListSpec {
  TodoListSpec(
    input_link_id: String,
    initial_titles: List(String),
    view_style: String,
    initial_theme: String,
  )
}
