import frontend/token.{type Span}

pub type Program {
  Program(definitions: List(Definition))
}

pub type Definition {
  Definition(name: String, value: Expression, span: Span)
}

pub type NamedArgument {
  NamedArgument(name: String, value: Expression)
}

pub type Expression {
  IntLiteral(Int)
  StringLiteral(String)
  BoolLiteral(Bool)
  TextLiteral(String)
  IdentifierRef(String)
  ListLiteral(List(Expression))
  Call(callee: String, arguments: List(NamedArgument))
  Record(name: String, fields: List(NamedArgument))
  FieldAccess(receiver: Expression, field: String)
  PipeCall(input: Expression, call: Expression)
  RawExpression(String)
}

pub fn definition_count(program: Program) -> Int {
  case program {
    Program(definitions) -> list_length(definitions, 0)
  }
}

fn list_length(items: List(a), count: Int) -> Int {
  case items {
    [] -> count
    [_, ..rest] -> list_length(rest, count + 1)
  }
}
