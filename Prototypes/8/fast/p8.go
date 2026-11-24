package fast

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
)

type (
	// Entry is one named payload: an encoded value (header 1) or program (header 2).
	Entry struct {
		Name string
		Payload []byte
	}

	// Bundle is the contents of a P8 file: the generation of the compiler that made its programs (0 when it was not made by the compiler), and its entries in order.
	Bundle struct {
		Generation uint64
		Entries []Entry
	}

	// p8Reader reads the lengths and bytes of a P8 file.
	p8Reader struct {
		b []byte
		p int
	}
)

// The P8 container (Prototypes/8/FORMAT.md): a file of named entries, each an encoded value or program (SPEC.md section 12), with a generation and a checksum. The encodings inside are the machine's own; the container adds only the names, the lengths, the generation, and the checksum.
//
// Layout: the magic "P8", the version (1), the generation (an unsigned LEB128 number), the entry count, the entries (each a name, then a payload, both with an unsigned LEB128 length), and a SHA-256 of everything before it. Lengths are unsigned LEB128.

const (
	p8Version = 1

	// p8Checksum is the length of the checksum at the end of a file.
	p8Checksum = sha256.Size
)

var (
	p8Magic = []byte{'P', '8'}

	// The stages of the compiler, in the order the pipeline runs them.
	stageNames = []string{"layout", "lex", "parse", "check", "desugar"}
)

// Entry returns the payload of the named entry.
func (b Bundle) Entry(name string) ([]byte, bool) {
	for _, e := range b.Entries {
		if e.Name == name {
			return e.Payload, true
		}
	}

	return nil, false
}

// ProgramBundle is a compiled program as a bundle: its law, under the name program.
func ProgramBundle(law *Law, gen uint64) (Bundle, error) {
	payload, err := EncodeProgram(law)
	if err != nil {
		return Bundle{}, err
	}

	return Bundle{
		Generation: gen,
		Entries: []Entry{
			{
				Name: "program",
				Payload: payload,
			},
		},
	}, nil
}

// SameStages reports whether two compilers have the same programs, stage by stage, and the stages that differ.
func SameStages(a, b Stages) (bool, []string, error) {
	var differ []string

	for _, name := range stageNames {
		x, err := EncodeProgram(a[name])
		if err != nil {
			return false, nil, err
		}

		y, err := EncodeProgram(b[name])
		if err != nil {
			return false, nil, err
		}

		if !bytes.Equal(x, y) {
			differ = append(differ, name)
		}
	}

	return len(differ) == 0, differ, nil
}

// StagesBundle is the stages of a compiler as a bundle of generation gen: one program entry per stage.
func StagesBundle(s Stages, gen uint64) (Bundle, error) {
	out := Bundle{
		Generation: gen,
	}

	for _, name := range stageNames {
		law := s[name]
		if law == nil {
			return Bundle{}, fmt.Errorf("no %s stage", name)
		}

		payload, err := EncodeProgram(law)
		if err != nil {
			return Bundle{}, fmt.Errorf("%s: %w", name, err)
		}

		out.Entries = append(out.Entries, Entry{
			Name: name,
			Payload: payload,
		})
	}

	return out, nil
}

// StagesFromBundle reads the stages of a compiler from a bundle: the program entry of each stage.
func StagesFromBundle(b Bundle) (Stages, error) {
	out := Stages{}

	for _, name := range stageNames {
		payload, ok := b.Entry(name)
		if !ok {
			return nil, fmt.Errorf("the bundle has no %s stage", name)
		}

		law, err := DecodeProgram(payload)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}

		out[name] = law
	}

	return out, nil
}

// ValueBundle is a value as a bundle, under the name value.
func ValueBundle(v Value) (Bundle, error) {
	payload, err := EncodeValue(v)
	if err != nil {
		return Bundle{}, err
	}

	return Bundle{
		Entries: []Entry{
			{
				Name: "value",
				Payload: payload,
			},
		},
	}, nil
}

func (r *p8Reader) bytes(n uint64, what string) ([]byte, error) {
	if n > uint64(len(r.b)-r.p) {
		return nil, fmt.Errorf("p8: %s has %d bytes, and only %d are left", what, n, len(r.b)-r.p)
	}

	out := r.b[r.p : r.p+int(n)]
	r.p += int(n)

	return out, nil
}

func (r *p8Reader) uvarint(what string) (uint64, error) {
	v, n := binary.Uvarint(r.b[r.p:])
	if n <= 0 {
		return 0, fmt.Errorf("p8: %s is missing or too long", what)
	}

	r.p += n

	return v, nil
}

// payloadKind checks the header byte of a payload: a value or a program.
func payloadKind(p []byte) (byte, error) {
	if len(p) == 0 {
		return 0, errors.New("p8: an entry has no payload")
	}

	switch p[0] {
	case programHeader, valueHeader:
		return p[0], nil
	}

	return 0, fmt.Errorf("p8: a payload has header %d, which is neither a value (%d) nor a program (%d)", p[0], valueHeader, programHeader)
}

// Encode writes the bundle as a P8 file.
func (b Bundle) Encode() ([]byte, error) {
	out := append([]byte{}, p8Magic...)
	out = append(out, p8Version)
	out = binary.AppendUvarint(out, b.Generation)
	out = binary.AppendUvarint(out, uint64(len(b.Entries)))

	for _, e := range b.Entries {
		if e.Name == "" {
			return nil, errors.New("p8: an entry has no name")
		}

		if _, err := payloadKind(e.Payload); err != nil {
			return nil, fmt.Errorf("p8: entry %s: %w", e.Name, err)
		}

		out = binary.AppendUvarint(out, uint64(len(e.Name)))
		out = append(out, e.Name...)
		out = binary.AppendUvarint(out, uint64(len(e.Payload)))
		out = append(out, e.Payload...)
	}

	sum := sha256.Sum256(out)

	return append(out, sum[:]...), nil
}

// DecodeBundle reads a P8 file, and checks its magic, its version, its checksum, its lengths and its payloads.
func DecodeBundle(data []byte) (Bundle, error) {
	// The magic, the version, a generation and a count (one byte each at least), and the checksum.
	if len(data) < len(p8Magic)+1+1+1+p8Checksum {
		return Bundle{}, errors.New("p8: the file is too short to be a P8 file")
	}

	if !bytes.Equal(data[:len(p8Magic)], p8Magic) {
		return Bundle{}, fmt.Errorf("p8: not a P8 file (it starts with %x)", data[:len(p8Magic)])
	}

	if v := data[len(p8Magic)]; v != p8Version {
		return Bundle{}, fmt.Errorf("p8: version %d; this reader reads version %d", v, p8Version)
	}

	body := data[:len(data)-p8Checksum]

	if sum := sha256.Sum256(body); !bytes.Equal(sum[:], data[len(data)-p8Checksum:]) {
		return Bundle{}, errors.New("p8: the checksum does not match: the file is damaged, or has been changed")
	}

	r := &p8Reader{
		b: body,
		p: len(p8Magic) + 1,
	}

	generation, err := r.uvarint("the generation")
	if err != nil {
		return Bundle{}, err
	}

	count, err := r.uvarint("the entry count")
	if err != nil {
		return Bundle{}, err
	}

	// Each entry takes at least three bytes (a name length, a name byte, and a payload length), so the count cannot be larger.
	if count > uint64(len(body)) {
		return Bundle{}, fmt.Errorf("p8: %d entries cannot fit in %d bytes", count, len(body))
	}

	out := Bundle{
		Generation: generation,
	}

	for range count {
		nameLen, err := r.uvarint("an entry's name length")
		if err != nil {
			return Bundle{}, err
		}

		nameBytes, err := r.bytes(nameLen, "an entry's name")
		if err != nil {
			return Bundle{}, err
		}

		if len(nameBytes) == 0 {
			return Bundle{}, errors.New("p8: an entry has no name")
		}

		payloadLen, err := r.uvarint(fmt.Sprintf("the payload length of %s", nameBytes))
		if err != nil {
			return Bundle{}, err
		}

		payload, err := r.bytes(payloadLen, fmt.Sprintf("the payload of %s", nameBytes))
		if err != nil {
			return Bundle{}, err
		}

		if _, err := payloadKind(payload); err != nil {
			return Bundle{}, fmt.Errorf("p8: entry %s: %w", nameBytes, err)
		}

		out.Entries = append(out.Entries, Entry{
			Name: string(nameBytes),
			Payload: append([]byte{}, payload...),
		})
	}

	if r.p != len(body) {
		return Bundle{}, fmt.Errorf("p8: %d bytes after the last entry", len(body)-r.p)
	}

	return out, nil
}

// ReadCompiler reads a compiler from a P8 file's bytes: its five stages, and the generation it records.
func ReadCompiler(data []byte) (Stages, uint64, error) {
	b, err := DecodeBundle(data)
	if err != nil {
		return nil, 0, err
	}

	stages, err := StagesFromBundle(b)
	if err != nil {
		return nil, 0, err
	}

	return stages, b.Generation, nil
}
