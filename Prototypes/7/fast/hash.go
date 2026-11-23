package fast

import (
	"crypto/sha256"
	"errors"
	"math/big"
)

// LawHash is the content hash of a law. It is computed once and kept on the law, so the machine can look a law up by its hash without writing it again.
func LawHash(l *Law) ([32]byte, error) {
	if l.hashed {
		return l.hash, nil
	}

	b, err := EncodeValue(l)
	if err != nil {
		return [32]byte{}, err
	}

	l.hash = sha256.Sum256(b[1:])
	l.hashed = true

	return l.hash, nil
}

func concat(parts ...[]byte) (out []byte) {
	for _, p := range parts {
		out = append(out, p...)
	}

	return
}

// leb is the LEB128 encoding of a magnitude (SPEC.md section 12.2).
func leb(n uint64) []byte {
	w := &writer{}

	w.mag(n)

	return w.buf
}

// The content hash of a value (SPEC.md section 12.7). An integer, nil or a law is the SHA-256 of its binary encoding without the header byte. A cell, a constructor, a partial application or a pin is the SHA-256 of a tag byte and its parts' hashes, so a new node costs one hash, once its parts are hashed; the result is kept on the node.
//
// Each hash also tells whether the value is data (SPEC.md section 7): an integer, nil, a cell or constructor of data, or a pin. A law, a partial application or a thunk is not data.

// hashOf gives the content hash of v, and whether v is data.
func hashOf(v Value) ([32]byte, bool, error) {
	switch x := v.(type) {
	case *App:
		if x.hashed {
			return x.hash, x.data, nil
		}

		parts := [][]byte{{'A'}}

		lh, _, err := hashOf(x.Law)
		if err != nil {
			return [32]byte{}, false, err
		}

		parts = append(parts, lh[:], leb(uint64(len(x.Args))))

		for _, a := range x.Args {
			ah, _, err := hashOf(a)
			if err != nil {
				return [32]byte{}, false, err
			}

			parts = append(parts, ah[:])
		}

		x.hash = sha256.Sum256(concat(parts...))
		x.data = false
		x.hashed = true

		return x.hash, x.data, nil
	case *Cell:
		if x.hashed {
			return x.hash, x.data, nil
		}

		hh, hd, err := hashOf(x.Head)
		if err != nil {
			return [32]byte{}, false, err
		}

		th, td, err := hashOf(x.Tail)
		if err != nil {
			return [32]byte{}, false, err
		}

		x.hash = sha256.Sum256(concat([]byte{'C'}, hh[:], th[:]))
		x.data = hd && td
		x.hashed = true

		return x.hash, x.data, nil
	case *Con:
		if x.hashed {
			return x.hash, x.data, nil
		}

		ph, pd, err := hashOf(x.Payload)
		if err != nil {
			return [32]byte{}, false, err
		}

		x.hash = sha256.Sum256(concat([]byte{'K'}, leb(uint64(x.Tag)), ph[:]))
		x.data = pd
		x.hashed = true

		return x.hash, x.data, nil
	case *Law:
		h, err := LawHash(x)

		return h, false, err
	case *Pin:
		if x.hashed {
			return x.hash, true, nil
		}

		vh, _, err := hashOf(x.Value)
		if err != nil {
			return [32]byte{}, false, err
		}

		x.hash = sha256.Sum256(concat([]byte{'P'}, vh[:]))
		x.data = true
		x.hashed = true

		return x.hash, true, nil
	case *Thunk:
		return [32]byte{}, false, errors.New("binary: a thunk has no binary form")
	case *big.Int, NilT, Small:
		b, err := EncodeValue(v)
		if err != nil {
			return [32]byte{}, false, err
		}

		return sha256.Sum256(b[1:]), true, nil
	}

	return [32]byte{}, false, errors.New("binary: a value of no kind")
}

// Hash is the content hash of a value (SPEC.md section 12.7).
func Hash(v Value) ([32]byte, error) {
	h, _, err := hashOf(v)

	return h, err
}
