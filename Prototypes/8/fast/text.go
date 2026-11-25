package fast

import (
	"fmt"
	"strings"
	"unicode/utf8"
)

// pipeSource is the text of a source file or an expression, as a list of codepoints: one item for each character, as the stages read it (SPEC.md section 2). The text must be UTF-8. A byte that does not belong to a valid character is an error, with its offset; so is a surrogate, which UTF-8 does not allow.
func pipeSource(s string) (Value, error) {
	items := make([]Value, 0, len(s))

	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		if r == utf8.RuneError && size == 1 {
			return nil, fmt.Errorf("the source is not UTF-8: the byte at offset %d is not part of a character", i)
		}

		items = append(items, Small(r))
		i += size
	}

	return pipeList(items), nil
}

// pipeText is the text of a list of codepoints, as UTF-8, for messages and digests. An item that is not a codepoint is written as "?".
func pipeText(v Value) string {
	var b strings.Builder

	for {
		c, ok := v.(*Cell)
		if !ok {
			break
		}

		s, ok := c.Head.(Small)
		if !ok || s < 0 || s > utf8.MaxRune || (s >= 0xD800 && s <= 0xDFFF) {
			b.WriteString("?")
		} else {
			b.WriteRune(rune(s))
		}

		v = c.Tail
	}

	return b.String()
}
