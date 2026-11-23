--!strict
-- THE TYPES OF THE PHASE 3 REFERENCE (SPEC.md sections 1 and 3)
--
-- Every value and form of the reference, as a type. A value is a number or a table with a kind; a form is a table with an op. The variants are discriminated by those fields, so a check on kind or op narrows the type.
-- An integer of any size: a number when exact, a big integer otherwise (int.luau).

export type Big = { kind: "big"; neg: boolean; bytes: { number } }
export type Int = number | Big
export type Nil = { kind: "nil" }
export type Cell = { kind: "cell"; head: Value; tail: Value }
export type Con = { kind: "con"; tag: number; payload: Value }
export type Law = { kind: "law"; arity: number; body: Form }
export type App = { kind: "app"; law: Law; args: { Value } }
export type Pin = { kind: "pin"; value: Value }
export type Thunk = { kind: "thunk"; f: Value; args: { Value }; done: boolean; result: Value? }
-- A value of the core: an integer, nil, a cell, a constructor, a function (a law, or a partial application), a pin, or a thunk.
export type Value = Int | Nil | Cell | Con | Law | App | Pin | Thunk
export type Lit = { op: "lit"; value: Value }
export type Arg = { op: "arg"; index: number }
export type Call = { op: "call"; f: Form; args: { Form } }
export type ConForm = { op: "con"; tag: number; e: Form }
export type Alt = { tag: number; body: Form }
export type Case = { op: "case"; e: Form; alts: { Alt }; elseBody: Form? }
export type If = { op: "if"; c: Form; t: Form; e: Form }
export type Let = { op: "let"; e: Form; body: Form }
export type Delay = { op: "delay"; call: Call }
export type Force = { op: "force"; e: Form }
export type Prim = { op: "prim"; tag: number; args: { Form } }
-- A form of the core (SPEC.md section 3). Each form has one of these shapes.
export type Form = Lit | Arg | Call | ConForm | Case | If | Let | Delay | Force | Prim
-- The outcome of a run: a value, an error with a message, or out of fuel. steps is the fuel used.
export type Outcome = { status: "value"; value: Value; steps: number } | { status: "error"; message: string; steps: number } | { status: "out_of_fuel"; steps: number }

return {}
