import frontend/ast.{type Definition, type Program, Program}

pub type HirProgram {
  HirProgram(definitions: List(Definition))
}

pub fn from_ast(program: Program) -> HirProgram {
  case program {
    Program(definitions) -> HirProgram(definitions)
  }
}
