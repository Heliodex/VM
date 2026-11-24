--!strict
-- GENERATES THE REFUSALS FIXTURE OF THE GO PIPELINE (Prototype 8, step 1)
--
-- For each malformed program of Prototypes/6/L2/malformed.luau: the stage that refuses it, as the bootstrapped compile gives it (boot_pipeline.luau), or "reader" when the host's file reader refuses the file before any stage runs; and the message. The Go tests (fast/refusals_test.go) must give the same stage, and a message that contains the case's reason.
--
-- The fields are hex, so a text may hold any bytes. Run from Prototypes/7/measure:
--   cd Prototypes/7/measure && lute run ../fast/gen/refusals.luau > ../fast/testdata/refusals.txt

const cases = require "../../../6/L2/malformed"
const ProgramFile = require "../../../6/L2/programfile"
const pipeline = require "../../measure/boot_pipeline"

const function hex(s: string): string
	return (
		string.gsub(
			s,
			".",
			function(c: string): string
				return string.format("%02x", string.byte(c))
			end
		)
	)
end

for _, case in cases do
	const readOk, readErr = pcall(ProgramFile.parse, case.text, case.name)

	if not readOk then
		print(`refusal reader {hex(case.text)} {hex(case.reason)} {hex(tostring(readErr))}`)
	else
		const compiled = pipeline.compileText(case.text, case.name, pipeline.loadFile)

		if compiled.ok then
			error(`{case.name}: the bootstrapped compile accepts a malformed program`, 0)
		end

		print(`refusal {compiled.stage} {hex(case.text)} {hex(case.reason)} {hex(compiled.message or "")}`)
	end
end
