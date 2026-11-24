--!strict
-- The malformed L2 programs of the test runners (l2_run.luau, and the bootstrapped compiler's runner in Prototypes/7/measure): each with a fragment of the reason it should be refused. A program file is text in the four-section format.

return {
	{
		name = "a list with a dot inside it",
		text = "h\n---\n---\n[1 . 2]\n---\n1 => 1 fuel 10\n",
		reason = "expected a value here",
	},
	{
		name = "a function whose body is on its parameters' line",
		text = "h\n---\n---\nfn x (+ x 1)\n---\n1 => 1 fuel 10\n",
		reason = "starts on the line after its parameters",
	},
	{
		name = "a cond with no _ clause",
		text = "h\n---\n---\ncond {\n\t(= 1 1) -> 2\n}\n---\n1 => 1 fuel 10\n",
		reason = "needs a _ clause as its last clause",
	},
	{
		name = "a cond clause after the _ clause",
		text = "h\n---\n---\ncond {\n\t_ -> 2\n\t(= 1 1) -> 3\n}\n---\n1 => 1 fuel 10\n",
		reason = "the _ clause of a cond is its last clause",
	},
	{
		name = "a letrec block that binds a non-function",
		text = "h\n---\n---\nletrec {\n\tx = 1\n\tx\n}\n---\n1 => 1 fuel 10\n",
		reason = "a letrec block binds fns",
	},
	{
		name = "a block with no body",
		text = "h\n---\n---\nlet {\n\tx = 1\n}\n---\n1 => 1 fuel 10\n",
		reason = "needs a body after its bindings",
	},
	{
		name = "a block whose body is not last",
		text = "h\n---\n---\nlet {\n\tx\n\ty = 1\n}\n---\n1 => 1 fuel 10\n",
		reason = "a block's body is its last item",
	},
	{
		name = "a whole integer that is not whole",
		text = "h\n---\n---\nfn x\n\t(+ 1-2 x)\n---\n1 => 1 fuel 10\n",
		reason = "is not a whole integer",
	},
	{
		name = "a ? in a non-tail if branch",
		text = "h\n---\n---\nfn s\n\t(let v = (if s (Err 1)? (Ok 2))\nv)\n---\n1 => 1 fuel 10\n",
		reason = "expected a value here",
	},
	{
		name = "a ? in a let value that is not the function's result",
		text = "h\n---\n---\nlet g = (fn x\n\tx)\nfn s\n\t(g (let v = s\nv?))\n---\n1 => 1 fuel 10\n",
		reason = "? can only be used where it runs whenever its function does",
	},
	{
		name = "a match with an arm after a catch-all",
		text = "h\n---\n---\nfn r\n\tmatch r {\n  x -> 1\n  Ok v -> 2\n}\n---\n1 => 1 fuel 10\n",
		reason = "unreachable",
	},
	{
		name = "a match arm body that runs past its line",
		text = "h\n---\n---\nfn r\n\tmatch r {\n  Ok v -> v? 2\n}\n---\n1 => 1 fuel 10\n",
		reason = "an arm ends at the end of its line",
	},
	{
		name = "a constructor bound as a name",
		text = "h\n---\n---\nlet Ok = 1\nOk\n---\n1 => 1 fuel 10\n",
		reason = "Ok cannot be bound by let",
	},
	{
		name = "a primitive bound as a name",
		text = "h\n---\n---\nlet + = 1\nfn x\n\tx\n---\n1 => 1 fuel 10\n",
		reason = "is a primitive, and cannot be bound",
	},
	{
		name = "a let that still has in",
		text = "h\n---\n---\nlet x = 1 in x\n---\n1 => 1 fuel 10\n",
		reason = "a let value ends at the end of its line",
	},
	{
		name = "a let inside a match arm",
		text = "h\n---\n---\nfn r\n\tmatch r {\n\tOk v -> let y = v\n\ty\n}\n---\n1 => 1 fuel 10\n",
		reason = "needs parentheses around it",
	},
	{
		name = "a letrec that does not bind a fn",
		text = "h\n---\n---\nletrec x = 1\nfn y\n\tx\n---\n1 => 1 fuel 10\n",
		reason = "letrec binds a fn",
	},
	{
		name = "a type declared twice with one constructor",
		text = "h\n---\n---\ntype A = Ok\ntype B = Ok\nOk\n---\n1 => 1 fuel 10\n",
		reason = "Ok is already declared",
	},
	{
		name = "an unbound name",
		text = "h\n---\n---\nfn x\n\ty\n---\n1 => 1 fuel 10\n",
		reason = "y is not bound",
	},
	{
		name = "an import of a file that is not there",
		text = "h\n---\nhelper = missing.prog\n---\nfn x\n\tx\n---\n1 => 1 fuel 10\n",
		reason = "cannot find missing.prog",
	},
	{
		name = "an argument of the wrong type",
		text = "h\n---\n---\nfn x\n\t(+ x [1])\n---\n1 => 1 fuel 10\n",
		reason = "expected Int, but this is [Int]",
	},
	{
		name = "an if condition that is a list",
		text = "h\n---\n---\nfn x\n\t(if [1] 1 2)\n---\n1 => 1 fuel 10\n",
		reason = "expected Int, but this is [Int]",
	},
	{
		name = "a value that contains itself",
		text = "h\n---\n---\nfn x\n\t(x x)\n---\n1 => 1 fuel 10\n",
		reason = "would be an infinite type",
	},
	{
		name = "a match that does not cover every constructor",
		text = "h\n---\n---\ntype Option a = None | Some a\nfn o\n\tmatch o {\n\tNone -> 0\n}\n---\n1 => 1 fuel 10\n",
		reason = "does not cover Some",
	},
	{
		name = "a pattern from another sum",
		text = "h\n---\n---\ntype A = X | Y\ntype B = P | Q\nfn a\n\tmatch a {\n\tX -> 0\n\tP -> 1\n}\n---\n1 => 1 fuel 10\n",
		reason = "P belongs to B",
	},
	{
		name = "a program that is not a function",
		text = "h\n---\n---\n1\n---\n1 => 1 fuel 10\n",
		reason = "must be a function of its input",
	},
	{
		name = "a ? in a function that does not return a Result",
		text = "h\n---\n---\nfn x\n\t(+ x (Ok 1)?)\n---\n1 => 1 fuel 10\n",
		reason = "expected",
	},
	{
		name = "a file with no tests",
		text = "h\n---\n---\nfn x\n\tx\n---\n\n",
		reason = "at least one test",
	},
}
