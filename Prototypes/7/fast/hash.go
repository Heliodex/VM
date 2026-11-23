package fast

import "crypto/sha256"

// Hash is the content hash of a value (SPEC.md section 12.7): the SHA-256 of its binary encoding, without the header byte. A value with no binary form has no hash, and gives the writer's error.
func Hash(v Value) ([32]byte, error) {
	b, err := EncodeValue(v)
	if err != nil {
		return [32]byte{}, err
	}

	return sha256.Sum256(b[1:]), nil
}

// LawHash is the content hash of a law. It is computed once and kept on the law, so the machine can look a law up by its hash without writing it again.
func LawHash(l *Law) ([32]byte, error) {
	if l.hashed {
		return l.hash, nil
	}

	h, err := Hash(l)
	if err != nil {
		return h, err
	}

	l.hash = h
	l.hashed = true

	return h, nil
}
