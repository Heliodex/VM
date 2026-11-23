package fast

// Jets for three of the corpus's helpers (fast/gen/gen.luau, section 9). Each is one match on a value, so each jet is a walk of that match: its cost is the entry and the match's arm, measured on the reference (the fixtures) and exact on every one of them.
//
//	check:first@19 (the checker's first, and the parser's): match (head l), Ok c -> c, Err -> -1. A cell costs 21 steps with the entry; anything else takes the Err arm, 67.
//	layout:hd@11: match (head l), Ok x -> x, Err -> 0. The same costs.
//	parse:kn@22: match (fst t), one arm per token kind 0 to 15, each giving its kind. The kind k costs 10 + 5k with the entry. A kind past 15, and a value that is not a token, is an error in the body, so the jet gives up there.

func init() {
	register("bf67082dcc14ec0804c7893707e92cdecc959f3e786498d28b6bb220ec7b7670", func(args []Value) (Value, int64, bool) {
		if c, ok := args[0].(*Cell); ok {
			return c.Head, 21, true
		}

		return Small(-1), 67, true
	})
	register("b5a7fd17c61e1218dbec3b963f1e2b5138649f330be896345940ee5d64ffe08f", func(args []Value) (Value, int64, bool) {
		if c, ok := args[0].(*Cell); ok {
			return c.Head, 21, true
		}

		return Small(0), 67, true
	})
	register("7d9cb981108e83e32c0aa4e35b89d68b15e48c88753de7d4465ee0788eef3949", func(args []Value) (Value, int64, bool) {
		c, ok := args[0].(*Cell)
		if !ok {
			return nil, 0, false
		}

		k, ok := c.Head.(*Con)
		if !ok || k.Tag < 0 || k.Tag > 15 {
			return nil, 0, false
		}

		return Small(k.Tag), int64(10 + 5*k.Tag), true
	})
}
