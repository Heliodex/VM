package fast

import (
	"encoding/hex"
	"testing"
)

// The vectors are SHA-256 of the bytes of each law's value encoding, computed with sha256sum (fast/README.md "Keys"), not by this package.
func TestHashVectors(t *testing.T) {
	cases := []struct {
		name,
		law, // the law's value encoding, which the hash is taken of, with its header byte
		hash string
	}{
		{"inc", "0105011a001101100201", "1b4ec34ddd5d101aad9fd9889cdf35b568a2b93f2a2061cc9819af67768bb2dd"},
		{"lit 7", "0105011002" + "07", "b054bc7b167ce04502994e247c5ba924519538ec316614abd0e914452665f27c"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			v, err := DecodeValue(unhex(t, c.law))
			if err != nil {
				t.Fatal(err)
			}

			h, err := Hash(v)
			if err != nil {
				t.Fatal(err)
			}

			if got := hex.EncodeToString(h[:]); got != c.hash {
				t.Fatalf("hash %s, want %s", got, c.hash)
			}

			l := v.(*Law)

			for range 2 {
				if lh, err := LawHash(l); err != nil || lh != h {
					t.Fatalf("law hash %x (%v), want %x", lh, err, h)
				}
			}
		})
	}
}
