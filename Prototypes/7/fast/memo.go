package fast

type (
	// MemoStats counts what the memo did since ResetMemo: hits and misses at memoised calls, the fuel the hits charged (the work they saved), and the entries stored.
	MemoStats struct {
		Hits, Misses, Stores, ChargedFuel int64
	}

	memoEntry struct {
		value Value
		fuel int64
	}
)

var (
	// MemoCounts is what the memo has done since the last ResetMemo.
	MemoCounts MemoStats

	// The memo (SPEC.md section 7). A saturated call of a law is memoised when every argument is data: its key is the law's content hash and the content hashes of its arguments (hash.go). A memo entry stores the call's result and the fuel the call used, counting its entry. A hit charges that stored fuel and does no work, so the fuel of a run is the same with the memo as without it. A hit that would run past the fuel is not taken: the body runs, and stops where the spec says.
	//
	// The table lives for the process, as the pin table does, so a second run of the same input is a hit at its top call. MemoOn turns it on; the results and the fuel do not depend on it.

	// MemoOn turns the memo on.
	MemoOn bool

	// MemoMinFuel is the least fuel a call must use to be stored: a smaller call saves little work, and its entry costs memory. The results and the fuel do not depend on it.
	MemoMinFuel int64 = 1000
	memo = map[string]memoEntry{}
)

// MemoSize is the number of entries in the memo.
func MemoSize() int {
	return len(memo)
}

// ResetMemo empties the memo and its counts.
func ResetMemo() {
	memo = map[string]memoEntry{}
	MemoCounts = MemoStats{}
}

// memoKey gives the key of a call of l with args, and whether the call is memoised. Every argument must have a content hash: a thunk does not (it is a delayed call, and it has no binary form).
func memoKey(l *Law, args []Value) (string, bool) {
	lh, err := LawHash(l)
	if err != nil {
		return "", false
	}

	key := make([]byte, 0, 32*(1+len(args)))
	key = append(key, lh[:]...)

	for _, a := range args {
		h, _, err := hashOf(a)
		if err != nil {
			return "", false
		}

		key = append(key, h[:]...)
	}

	return string(key), true
}
