package fast

// Jets for three of the desugarer's list walks (Prototypes/8/l2/programs/boot/desugar.l2), each a loop over a list that calls the desugarer's same on each item, as posIn does (desugarjets.go):
//
//   inList (names s): 1 if a name is the name s, else 0.
//   primIn (tbl s): the value of the first entry whose key is s, else -1.
//   lookupCtorFrom (tbl name): the value of the first entry whose key is name, else CNone.
//
// Each jet gives up on anything the body would not walk as a list of names or of (key . value) entries, so an error keeps the body's outcome. Its cost is the arms its walk takes, each at its fitted cost, and the cost of its calls of same (desugarwalks_fit_test.go).

const (
	inNext = iota
	inFound
	inNil
	inArms
)

const (
	assocNext = iota
	assocFound
	assocNil
	assocArms
)

var (
	// inListHash is desugar:inList@41, arity 4: the head function, the same applied to it, the names and the name.
	inListHash = mustHash("2d2301fa008cf940fed81e82e777223a3938b6b0456fa6fcb5da3d60048fcc17")

	// primInHash is desugar:primIn@57, arity 4: the same arguments, with the table and the name.
	primInHash = mustHash("3b37284e9594171d9611d24c801f74141cbda5bd610cc418ae035a609538df6e")

	// lookupCtorFromHash is desugar:lookupCtorFrom@120, arity 4: the same arguments, with the table and the name.
	lookupCtorFromHash = mustHash("8a8d06ac550bc9f3aacdce81fbf33132868978f3867dea6a8097a3da5670ba1e")

	// costInList is the cost of each arm of inList, in steps, counting its entry and its own forms but not its calls of same (fitted).
	costInList = [inArms]int64{46, 27, 7}

	// costAssocPrimIn and costAssocLookup are the cost of each arm of primIn and of lookupCtorFrom, the same way (fitted).
	costAssocPrimIn = [assocArms]int64{49, 48, 7}
	costAssocLookup = [assocArms]int64{50, 50, 8}

	// ctorNone is CNone, the first constructor of the desugarer's Ctor: tag 0, with payload ~.
	ctorNone = &Con{Tag: 0, Payload: NIL}
)

// inListWalk is inList on a list of names and the name s: the result, the arms its walk takes, and the cost of its calls of same. It gives up on anything the body would not compare.
func inListWalk(names, s Value) (res Value, arms [inArms]int64, sameCost int64, ok bool) {
	if !isListValue(s) {
		return nil, arms, 0, false
	}

	for {
		c, isCell := names.(*Cell)
		if !isCell {
			if _, isNil := names.(NilT); !isNil {
				return nil, arms, 0, false
			}

			arms[inNil]++

			return Small(0), arms, sameCost, true
		}

		if !isListValue(c.Head) {
			return nil, arms, 0, false
		}

		var w [sameArms]int64

		found, ok := sameWalk(c.Head, s, &w)
		if !ok {
			return nil, arms, 0, false
		}

		for k := range w {
			sameCost += w[k] * costDesugarSame[k]
		}

		if found == Small(1) {
			arms[inFound]++

			return Small(1), arms, sameCost, true
		}

		arms[inNext]++
		names = c.Tail
	}
}

// assocWalk is primIn or lookupCtorFrom on a table of (key . value) entries and the name key: the value of the first entry whose key is the name, or nilRes when there is none, with the arms its walk takes and the cost of its calls of same.
func assocWalk(tbl, key, nilRes Value) (res Value, arms [assocArms]int64, sameCost int64, ok bool) {
	if !isListValue(key) {
		return nil, arms, 0, false
	}

	for {
		c, isCell := tbl.(*Cell)
		if !isCell {
			if _, isNil := tbl.(NilT); !isNil {
				return nil, arms, 0, false
			}

			arms[assocNil]++

			return nilRes, arms, sameCost, true
		}

		entry, isPair := c.Head.(*Cell)
		if !isPair || !isListValue(entry.Head) {
			return nil, arms, 0, false
		}

		var w [sameArms]int64

		found, ok := sameWalk(entry.Head, key, &w)
		if !ok {
			return nil, arms, 0, false
		}

		for k := range w {
			sameCost += w[k] * costDesugarSame[k]
		}

		if found == Small(1) {
			arms[assocFound]++

			return entry.Tail, arms, sameCost, true
		}

		arms[assocNext]++
		tbl = c.Tail
	}
}

// sameApplied is whether v is the desugarer's same applied to the head function, as the walks' callers pass it.
func sameApplied(v Value) bool {
	app, isApp := v.(*App)

	return isApp && len(app.Args) == 1 && lawIs(app.Args[0], hdHash) && lawIs(app.Law, sameHash)
}

func init() {
	// inList@41: arity 4. Its arguments are the head function, the same applied to it, the names and the name.
	register("2d2301fa008cf940fed81e82e777223a3938b6b0456fa6fcb5da3d60048fcc17", func(args []Value) (Value, int64, bool) {
		if !lawIs(args[0], hdHash) || !sameApplied(args[1]) {
			return nil, 0, false
		}

		res, arms, sameCost, ok := inListWalk(args[2], args[3])
		if !ok {
			return nil, 0, false
		}

		cost := sameCost

		for k := range arms {
			cost += arms[k] * costInList[k]
		}

		return res, cost, true
	})

	// primIn@57: arity 4, with the same arguments as inList.
	register("3b37284e9594171d9611d24c801f74141cbda5bd610cc418ae035a609538df6e", func(args []Value) (Value, int64, bool) {
		if !lawIs(args[0], hdHash) || !sameApplied(args[1]) {
			return nil, 0, false
		}

		res, arms, sameCost, ok := assocWalk(args[2], args[3], Small(-1))
		if !ok {
			return nil, 0, false
		}

		cost := sameCost

		for k := range arms {
			cost += arms[k] * costAssocPrimIn[k]
		}

		return res, cost, true
	})

	// lookupCtorFrom@120: arity 4, with the same arguments as inList.
	register("8a8d06ac550bc9f3aacdce81fbf33132868978f3867dea6a8097a3da5670ba1e", func(args []Value) (Value, int64, bool) {
		if !lawIs(args[0], hdHash) || !sameApplied(args[1]) {
			return nil, 0, false
		}

		res, arms, sameCost, ok := assocWalk(args[2], args[3], ctorNone)
		if !ok {
			return nil, 0, false
		}

		cost := sameCost

		for k := range arms {
			cost += arms[k] * costAssocLookup[k]
		}

		return res, cost, true
	})
}
