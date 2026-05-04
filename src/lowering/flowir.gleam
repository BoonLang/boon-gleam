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
  StaticDocument(buttons: List(FlowStaticButton))
  NumericText(buttons: List(FlowButton))
  AppendTextList(AppendTextListSpec)
  CheckboxList(CheckboxListSpec)
  CountList(CountListSpec)
  CrudList(CrudListSpec)
  FlightBooker
  LatestValue
  RepeatedButtonList(RepeatedButtonListSpec)
  RouterPages(RouterPagesSpec)
  SwitchHold
  TemperatureConverter
  TimerOperation(TimerOperationSpec)
  IntervalAccumulator
  TimerWidget(TimerWidgetSpec)
  ToggleText(ToggleTextSpec)
  StableList(StableListSpec)
  ShoppingList(ShoppingListSpec)
  TodoList(TodoListSpec)
}

pub type FlowStaticButton {
  FlowStaticButton(label: String)
}

pub type FlowButton {
  FlowButton(label: String, delta: Int)
}

pub type AppendTextListSpec {
  AppendTextListSpec(initial_items: List(String), render_mode: String)
}

pub type FlowListItem {
  FlowListItem(id: Int, name: String)
}

pub type CheckboxListSpec {
  CheckboxListSpec(
    initial_labels: List(String),
    filterable: Bool,
    instructions: String,
  )
}

pub type CountListSpec {
  CountListSpec(title: String, undo_label: String, count_label: String)
}

pub type FlowPerson {
  FlowPerson(name: String, surname: String)
}

pub type CrudListSpec {
  CrudListSpec(initial_people: List(FlowPerson))
}

pub type ToggleTextSpec {
  ToggleTextSpec(off_text: String, on_text: String)
}

pub type TimerOperationSpec {
  TimerOperationSpec(mode: String, buttons: List(String))
}

pub type RepeatedButtonListSpec {
  RepeatedButtonListSpec(
    title: String,
    button_label: String,
    count_label: String,
    item_count: Int,
  )
}

pub type RouterPagesSpec {
  RouterPagesSpec(
    nav_labels: List(String),
    home_title: String,
    home_description: String,
    about_title: String,
    about_description: String,
    contact_title: String,
    contact_description: String,
  )
}

pub type TimerWidgetSpec {
  TimerWidgetSpec(
    title: String,
    elapsed_label: String,
    duration_label: String,
    reset_label: String,
    initial_duration: Int,
  )
}

pub type StableListSpec {
  StableListSpec(
    title: String,
    add_label: String,
    clear_completed_label: String,
    initial_items: List(FlowListItem),
    next_id: Int,
  )
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
