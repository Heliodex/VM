package fast

import (
	"bytes"
	"crypto/sha256"
	"strings"
	"testing"
)

// TestCompilerFile checks that a compiler written as a P8 file reads back to the same stages, and that a compiler read from the file compiles a program the way the seed does.
func TestCompilerFile(t *testing.T) {
	seed, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	b, err := StagesBundle(seed, 5)
	if err != nil {
		t.Fatal(err)
	}

	data, err := b.Encode()
	if err != nil {
		t.Fatal(err)
	}

	stages, gen, err := ReadCompiler(data)
	if err != nil {
		t.Fatal(err)
	}

	if gen != 5 {
		t.Errorf("the generation reads back as %d, want 5", gen)
	}

	same, differ, err := SameStages(seed, stages)
	if err != nil || !same {
		t.Fatalf("the stages read back differently (%v, %v)", differ, err)
	}

	text, ok := programLoader("lib/abs.l2")
	if !ok {
		t.Fatal("no lib/abs.l2")
	}

	c, err := stages.Compile(text, "lib/abs.l2", programLoader)
	if err != nil {
		t.Fatal(err)
	}

	if got := c.Run(Small(-7), 1<<20); got.Status != "value" || got.Value != Small(7) {
		t.Errorf("abs -7 with the compiler from the file: %s %v", got.Status, got.Value)
	}
}

// TestProgramFile compiles a program file, writes it as a P8 file, reads it back, and runs it on the machine: the file runs without the compiler.
func TestProgramFile(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	text, ok := programLoader("lib/abs.l2")
	if !ok {
		t.Fatal("no lib/abs.l2")
	}

	c, err := stages.Compile(text, "lib/abs.l2", programLoader)
	if err != nil {
		t.Fatal(err)
	}

	gen, err := SeedGeneration()
	if err != nil {
		t.Fatal(err)
	}

	b, err := ProgramBundle(c.Law, gen)
	if err != nil {
		t.Fatal(err)
	}

	data, err := b.Encode()
	if err != nil {
		t.Fatal(err)
	}

	back, err := DecodeBundle(data)
	if err != nil {
		t.Fatal(err)
	}

	payload, ok := back.Entry("program")
	if !ok {
		t.Fatal("no program entry")
	}

	law, err := DecodeProgram(payload)
	if err != nil {
		t.Fatal(err)
	}

	for _, c := range []struct {
		in, out int64
	}{
		{-7, 7},
		{0, 0},
		{5, 5},
	} {
		if got := Run(law, Small(c.in), 1<<20); got.Status != "value" || got.Value != Small(c.out) {
			t.Errorf("abs %d: %s %v, want %d", c.in, got.Status, got.Value, c.out)
		}
	}
}

// TestSeedFile checks that the seed is a canonical P8 file: decoding it and encoding it again gives its own bytes, and it holds the five stages, which decode as programs.
func TestSeedFile(t *testing.T) {
	b, err := SeedBundle()
	if err != nil {
		t.Fatal(err)
	}

	data, err := b.Encode()
	if err != nil {
		t.Fatal(err)
	}

	if !bytes.Equal(data, seedSource) {
		t.Error("the seed does not encode to its own bytes")
	}

	if b.Generation != 9 {
		t.Errorf("the seed is generation %d, want 9", b.Generation)
	}

	if _, err := SeedStages(); err != nil {
		t.Error(err)
	}
}

// sampleBundle is a bundle with a value and a program, for the round-trip test.
func sampleBundle(t *testing.T) Bundle {
	t.Helper()

	value := &Cell{
		Head: Small(1),
		Tail: &Cell{
			Head: Small(2),
			Tail: NIL,
		},
	}

	v, err := ValueBundle(value)
	if err != nil {
		t.Fatal(err)
	}

	p, err := ProgramBundle(&Law{
		Arity: 1,
		Body: argNode(1),
	}, 7)
	if err != nil {
		t.Fatal(err)
	}

	return Bundle{
		Generation: 7,
		Entries: []Entry{v.Entries[0], p.Entries[0]},
	}
}

// TestBundleRoundTrip checks that a bundle encodes, decodes to the same entries and generation, and encodes to the same bytes again.
func TestBundleRoundTrip(t *testing.T) {
	b := sampleBundle(t)

	data, err := b.Encode()
	if err != nil {
		t.Fatal(err)
	}

	back, err := DecodeBundle(data)
	if err != nil {
		t.Fatal(err)
	}

	if back.Generation != b.Generation || len(back.Entries) != len(b.Entries) {
		t.Fatalf("decoded generation %d with %d entries, want %d with %d", back.Generation, len(back.Entries), b.Generation, len(b.Entries))
	}

	for i := range b.Entries {
		if back.Entries[i].Name != b.Entries[i].Name || !bytes.Equal(back.Entries[i].Payload, b.Entries[i].Payload) {
			t.Errorf("entry %d differs after the round trip", i)
		}
	}

	again, err := back.Encode()
	if err != nil || !bytes.Equal(again, data) {
		t.Errorf("re-encoding gives other bytes (%v)", err)
	}
}

// withChecksum recomputes a P8 file's checksum after its body was changed, so that a test reaches the check after the checksum.
func withChecksum(body []byte) []byte {
	sum := sha256.Sum256(body)

	return append(append([]byte{}, body...), sum[:]...)
}

// TestBundleRefusals checks that each kind of damage is refused, with a message that names it.
func TestBundleRefusals(t *testing.T) {
	good, err := sampleBundle(t).Encode()
	if err != nil {
		t.Fatal(err)
	}

	body := good[:len(good)-sha256.Size]
	cases := []struct {
		name string
		data []byte
		want string
	}{
		{"too short", good[:5], "too short"},
		{"bad magic", append([]byte("XX"), good[2:]...), "not a P8 file"},
		{
			"a later version",
			func() []byte {
				b := append([]byte{}, body...)
				b[2] = 2

				return withChecksum(b)
			}(),
			"version 2",
		},
		{
			"a changed byte",
			func() []byte {
				b := append([]byte{}, good...)
				b[len(b)/2] ^= 1

				return b
			}(),
			"checksum",
		},
		{"truncated", good[:len(good)-1], "checksum"},
		{"bytes after the checksum", append(append([]byte{}, good...), 0), "checksum"},
		{
			"a payload that is neither a value nor a program",
			func() []byte {
				b := append([]byte{}, body...)
				// The first payload's header byte follows its name and its length: "value" is 5 bytes, and the payload's length is one byte.
				i := bytes.Index(b, []byte("value")) + len("value") + 1
				b[i] = 9

				return withChecksum(b)
			}(),
			"neither a value",
		},
		{
			"more entries than bytes",
			func() []byte {
				b := append([]byte{}, body[:3]...)
				b = append(b, 0x7f, 0x7f)

				return withChecksum(b)
			}(),
			"cannot fit",
		},
		{
			"bytes after the last entry",
			withChecksum(append(append([]byte{}, body...), 0, 0)),
			"after the last entry",
		},
	}

	for _, c := range cases {
		_, err := DecodeBundle(c.data)
		if err == nil {
			t.Errorf("%s: accepted", c.name)
			continue
		}

		if !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: %q, want a message with %q", c.name, err.Error(), c.want)
		}
	}
}
