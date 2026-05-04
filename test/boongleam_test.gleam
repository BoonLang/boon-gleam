import backend/session
import cli/command
import frontend/diagnostic
import gleam/list
import gleam/option.{Some}
import gleeunit
import playground/core as playground_core
import project/loader
import project/project as project_model
import support/version
import verify/expected

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn phase_marker_test() {
  assert command.phase == "phase_11_plus_performance"
  assert version.implementation_phase == "Phase 11 + Performance"
}

pub fn expected_parser_handles_multi_action_rows_test() {
  let contents =
    "[test]\n"
    <> "category = \"interactive\"\n"
    <> "\n"
    <> "[output]\n"
    <> "text = \"0 items\"\n"
    <> "\n"
    <> "[[sequence]]\n"
    <> "actions = [[\"type\", \"Milk\"], [\"key\", \"Enter\"], [\"assert_not_contains\", \"[object]\"]]\n"
    <> "expect = \"1 items\"\n"

  let assert Ok(expected.Expected(text, steps)) =
    expected.parse_text("fixture.expected", contents)
  assert text == "0 items"
  let assert [expected.ExpectedStep(expected.SequenceStep, actions, "1 items")] =
    steps
  assert actions
    == [
      expected.TypeText("Milk"),
      expected.KeyPress("Enter"),
      expected.AssertNotContains("[object]"),
    ]
}

pub fn expected_parser_marks_persistence_steps_test() {
  let contents =
    "[output]\n"
    <> "text = \"0+\"\n"
    <> "\n"
    <> "[[sequence]]\n"
    <> "actions = [[\"click_button\", 0]]\n"
    <> "expect = \"1+\"\n"
    <> "\n"
    <> "[[persistence]]\n"
    <> "expect = \"1+\"\n"

  let assert Ok(expected.Expected(_, steps)) =
    expected.parse_text("fixture.expected", contents)
  let assert [
    expected.ExpectedStep(expected.SequenceStep, _, "1+"),
    expected.ExpectedStep(expected.PersistenceStep, [], "1+"),
  ] = steps
}

pub fn expected_parser_rejects_unknown_actions_test() {
  let contents =
    "[output]\n"
    <> "text = \"ok\"\n"
    <> "\n"
    <> "[[sequence]]\n"
    <> "actions = [[\"not_a_real_action\"]]\n"
    <> "expect = \"ok\"\n"

  let assert Error([diagnostic.Diagnostic(code: code, ..), ..]) =
    expected.parse_text("fixture.expected", contents)
  assert code == "expected_parse_failed"
}

pub fn expected_parser_allows_sequence_only_files_test() {
  let contents =
    "[test]\n"
    <> "category = \"interactive\"\n"
    <> "\n"
    <> "[[sequence]]\n"
    <> "actions = [[\"assert_cells_cell_text\", 1, 1, \"5\"]]\n"

  let assert Ok(expected.Expected(text, steps)) =
    expected.parse_text("fixture.expected", contents)
  assert text == ""
  let assert [
    expected.ExpectedStep(
      expected.SequenceStep,
      [expected.AssertCellsCellText(1, 1, "5")],
      "",
    ),
  ] = steps
}

pub fn loader_imports_build_project_manifest_test() {
  let assert Ok(project_model.Project(
    entry_file: entry_file,
    files: files,
    project_files: project_files,
    assets_root: Some("assets"),
    build_report: Some(build_report),
    ..,
  )) = loader.load("examples/upstream/todo_mvc_physical")

  assert entry_file.path == "examples/upstream/todo_mvc_physical/RUN.bn"
  assert list.length(files) == 7
  assert list.length(project_files) == 8
  assert list.any(project_files, fn(file) {
    file.path == "Generated/Assets.bn" && file.generated
  })

  let assert project_model.BuildReport(
    path: "BUILD.bn",
    generated_files: ["Generated/Assets.bn"],
    input_files: [
      "assets/icons/checkbox_active.svg",
      "assets/icons/checkbox_completed.svg",
    ],
    succeeded: True,
    ..,
  ) = build_report
}

pub fn backend_session_rejects_stale_and_reuses_duplicates_test() {
  let started =
    session.start(
      "examples/upstream/counter",
      session.Memory,
      "backend session ready",
    )
  let assert Ok(#(after_first, first_result)) =
    session.accept_event(started, "event-1", 0, "click")
  assert first_result.revision == 1

  let assert Ok(#(_, duplicate_result)) =
    session.accept_event(after_first, "event-1", 0, "click")
  assert duplicate_result.revision == 1
  assert duplicate_result.snapshot_text == first_result.snapshot_text

  let assert Error(session.RevisionConflict(current_revision: 1)) =
    session.accept_event(after_first, "event-stale", 0, "click")
}

pub fn playground_catalog_exposes_three_platform_examples_test() {
  let assert Ok(example) = playground_core.find_example("counter")

  assert example.path == "examples/upstream/counter"
  assert example.terminal == playground_core.PlatformReady
  assert example.native == playground_core.PlatformReady
  assert example.browser == playground_core.PlatformReady
}

pub fn playground_scene_preserves_source_and_runtime_snapshot_test() {
  let assert Ok(scene) =
    playground_core.scene("counter", playground_core.BrowserGuiTarget)

  assert scene.example.name == "counter"
  assert scene.source_path == "examples/upstream/counter/counter.bn"
  assert scene.snapshot_text == "0+"
  assert scene.commands != []
  assert scene.hit_regions != []

  let proof = playground_core.proof("test", scene)
  assert proof.status == "pass"
  assert proof.runtime_origin == "generated-boon-gleam-core"
}
