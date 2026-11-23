package fast

import "encoding/hex"

// Jets (SPEC.md section 3, decision 11). A jet is native code that replaces the body of one law. The machine chooses it by the law's content hash (section 12.7), so a program never names a jet: it has the law or it does not.
//
// The rules that keep a jet exact (decision 11):
//
//   - A jet declares the fuel of the law's body on the inputs it handles: the entry (one step) and every step of the body. The machine charges that fuel in one go.
//   - A jet handles only the inputs it has checked, and gives up on anything else (ok false). The body then runs, so every error, and the point where a run runs out of fuel, are the spec's.
//   - A jet is used only when the whole call fits in the fuel. If it does not, the body runs and stops at the same step the spec says.
//   - The jet table is fixed in the build. A program cannot add to it.
//
// Each jet's fuel is measured on the reference (fast/gen/gen.luau writes the calls and their steps), and the tests check every one, so a wrong number fails there.

// jetFn runs a law's body natively on its arguments. It gives the result and the fuel the body would use, counting the entry, or ok false when the body must run instead.
type jetFn func(args []Value) (result Value, fuel int64, ok bool)

var (
	// JetsOn turns the table on. The tests run with it off as well, to show that the spec code alone gives the same results and steps.
	JetsOn = true

	// jets is the table of jets, by the content hash of the law each replaces.
	jets = map[[32]byte]jetFn{}
)

// jetFor is the jet of a law, or nil when the law has none.
func jetFor(l *Law) jetFn {
	if len(jets) == 0 {
		return nil
	}

	h, err := LawHash(l)
	if err != nil {
		return nil
	}

	return jets[h]
}

func register(lawHash string, fn jetFn) {
	b, err := hex.DecodeString(lawHash)
	if err != nil || len(b) != 32 {
		panic("fast: a jet's hash is not 32 bytes of hex: " + lawHash)
	}

	var h [32]byte

	copy(h[:], b)

	jets[h] = fn
}

func init() {
	// tl (measure/boot/types.l2, line 24): match (tail l), Ok t -> t, Err -> nil. Measured: a cell takes 27 steps with the entry, nil takes 73.
	register("946d5f34067872fe9c5fa066e42bc19bafd80f03f99ee40ba1e7e41a5175f1a1", func(args []Value) (Value, int64, bool) {
		switch l := args[0].(type) {
		case *Cell:
			return l.Tail, 27, true
		case NilT:
			return NIL, 73, true
		}

		return nil, 0, false
	})

	// hdOr (line 14), the inner law of two arguments (the list, then the default): match (head l), Ok x -> x, Err -> dflt. Measured: a cell takes 29 steps with the entry, nil takes 77.
	register("752c09cccd9206aa0ce94b38edebd9776174d23f6485121cde4340b0e0dcf20e", func(args []Value) (Value, int64, bool) {
		switch l := args[0].(type) {
		case *Cell:
			return l.Head, 29, true
		case NilT:
			return args[1], 77, true
		}

		return nil, 0, false
	})

	// stP (line 63): match st, St p -> p. Measured: a St constructor (tag 0) takes 16 steps with the entry. Any other value is an error in the body, so it is left to the body.
	register("700b448d63d5635a60e6d892e13ae2a055dcd35950e71d02e34e5c159d8f6d96", func(args []Value) (Value, int64, bool) {
		if c, ok := args[0].(*Con); ok && c.Tag == 0 {
			return c.Payload, 16, true
		}

		return nil, 0, false
	})
}
