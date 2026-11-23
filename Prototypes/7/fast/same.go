package fast

// The jet for same (measure/boot/types.l2, owner same@39): the name comparison, two lists compared a byte at a time. Its body, as a walk of the same paths:
//
//	armNilB   a is not a cell and b is nil: 1
//	armNotB   a is not a cell and b is not nil: 0
//	armBNot   a is a cell and b is not: 0
//	armDiffer both are cells and their heads differ: 0
//	armStep   both are cells and their heads are equal: compare the tails (one more level)
//
// Each level is one entry of the law. The elements must be integers, since `=` refuses anything else, and the walk gives up on those, so the body runs and gives the error.
const (
	armNilB = iota
	armNotB
	armBNot
	armDiffer
	armStep
	sameArms
)

// costSame is the cost of each arm, in steps, counting the entry (fitted; see same_test.go).
var costSame = [sameArms]int64{79, 79, 111, 84, 159}

// sameWalk is same: the result, and the arms its path takes.
func sameWalk(a, b Value, w *[sameArms]int64) (Value, bool) {
	for {
		ac, aCell := a.(*Cell)
		if !aCell {
			if _, bNil := b.(NilT); bNil {
				w[armNilB]++

				return Small(1), true
			}

			w[armNotB]++

			return Small(0), true
		}

		bc, bCell := b.(*Cell)
		if !bCell {
			w[armBNot]++

			return Small(0), true
		}

		if !isInt(ac.Head) || !isInt(bc.Head) {
			return nil, false
		}

		if compare(ac.Head, bc.Head) != 0 {
			w[armDiffer]++

			return Small(0), true
		}

		w[armStep]++
		a, b = ac.Tail, bc.Tail
	}
}

func init() {
	// same@39: arity 2, the two names. The hash is the law's content hash (sha256 of its encoding, section 12.7).
	register("3200d4c23d5ab84fcb74f9ac562f3150f1322db7706697bed9cf6a56eaea3953", func(args []Value) (Value, int64, bool) {
		var w [sameArms]int64

		res, ok := sameWalk(args[0], args[1], &w)
		if !ok {
			return nil, 0, false
		}

		var cost int64

		for i := range w {
			cost += w[i] * costSame[i]
		}

		return res, cost, true
	})
}
