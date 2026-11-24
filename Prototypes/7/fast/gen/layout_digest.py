"""Turns the output of gen/layout.luau into the layout fixture (testdata/layout.txt).

gen/layout.luau prints each input's layout output as hex. A text is kept as its SHA-256 (the fixture stays small: the texts of the whole program files are most of the size), and an error keeps its message. The Go test (layout_test.go) rebuilds each input from the program files and compares the digest or the message.

Usage (from Prototypes/7/measure):
    lute run ../fast/gen/layout.luau | python3 ../fast/gen/layout_digest.py > ../fast/testdata/layout.txt
"""
import hashlib
import sys

for line in sys.stdin:
    fields = line.split()

    if len(fields) != 4 or fields[0] != "layout":
        continue

    name, kind, payload = fields[1], fields[2], fields[3]

    if kind == "text":
        payload = hashlib.sha256(bytes.fromhex(payload)).hexdigest()

    print(f"layout {name} {kind} {payload}")
