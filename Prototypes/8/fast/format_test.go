package fast

import (
	"strings"
	"testing"
)

// The reserved and unused tags of the binary format are refused (SPEC.md section 12.3 and 12.4), as the Luau reference refuses them (reference/format_run.luau): value tag 7, which was a pin in Prototypes 5 and 6 and is reserved since decision 16, and form tag 19, which is unused.
func TestReservedTagsRefused(t *testing.T) {
	if _, err := DecodeValue([]byte{1, 7}); err == nil || !strings.Contains(err.Error(), "tag 7 is not a value") {
		t.Fatalf("value tag 7: got %v", err)
	}

	if _, err := DecodeProgram([]byte{2, 1, 19}); err == nil || !strings.Contains(err.Error(), "tag 19 is not a form") {
		t.Fatalf("form tag 19: got %v", err)
	}
}
