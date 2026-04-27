import frontend/token.{type Span}

pub type SourceShape {
  SourceShape(
    source_slot_id: String,
    semantic_path: String,
    payload_type: String,
    source_span: Span,
    binding_target_path: String,
    function_instance_id: String,
    mapped_scope_id: String,
    list_item_identity_input: String,
    pass_context_path: String,
  )
}
