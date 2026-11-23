package fast

// Jets for three of the corpus's helpers (fast/gen/gen.luau, section 9). Each is one match on a value, so each jet is a walk of that match: its cost is the entry and the match's arm, measured on the reference (the fixtures) and exact on every one of them.
//
//	check:first@19 (the checker's first, and the parser's): match (head l), Ok c -> c, Err -> -1. A cell costs 21 steps with the entry; anything else takes the Err arm, 67.
//	layout:hd@11: match (head l), Ok x -> x, Err -> 0. The same costs.
//	parse:kn@22: match (fst t), one arm per token kind 0 to 15, each giving its kind. The kind k costs 10 + 5k with the entry. A kind past 15, and a value that is not a token, is an error in the body, so the jet gives up there.

func init() {
	register("16d3656bc970da32c091e35268de28d47bcc45265f02ca09cd4c40b7c55c7f07", func(args []Value) (Value, int64, bool) {
		if c, ok := args[0].(*Cell); ok {
			return c.Head, 21, true
		}

		return Small(-1), 67, true
	})
	register("0505ca94a523f75a5f7dea44ed55788d6a7c9efa2092b1b926a5f92728831134", func(args []Value) (Value, int64, bool) {
		if c, ok := args[0].(*Cell); ok {
			return c.Head, 21, true
		}

		return Small(0), 67, true
	})
	register("7b0ca954e437bbd58f42d10b9950b924bb70980c402b5003b77e7df3129478a6", func(args []Value) (Value, int64, bool) {
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
