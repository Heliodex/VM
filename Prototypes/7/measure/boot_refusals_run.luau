--!strict
-- CHECKS THE REFUSALS OF THE BOOTSTRAPPED COMPILER: each malformed program of Prototypes/6/L2/malformed.luau is run through the L2 stages, and the stage that refuses it must give the reason the case names
--
-- A malformed program is refused by the stage that finds the fault: the layout, the tokenizer, the parser, the checker or the desugarer. Its message must contain the case's reason. The host reads the file format (the sections, the test lines) before any stage runs; a case that the host reader refuses is reported as such, since that part is not bootstrapped. A case the stages accept is a failure.
--
--   lute run boot_refusals_run.luau      (from Prototypes/7/measure)

const cases = require "../../6/L2/malformed"
const ProgramFile = require "../../6/L2/programfile"
const pipeline = require "./boot_pipeline"

local failures = 0
local passes = 0
local readerRefusals = 0

for _, case in cases do
	-- The host reads the file format first. A file it refuses is not a program the stages see.
	const readOk, readErr = pcall(ProgramFile.parse, case.text, case.name)

	if not readOk then
		readerRefusals += 1
		const readMessage = tostring(readErr)

		if string.find(readMessage, case.reason, 1, true) ~= nil then
			passes += 1
			print(`PASS  {case.name}: refused by the host reader: {readMessage}`)
		else
			failures += 1
			print(`FAIL  {case.name}: the host reader says {readMessage}, the case expects {case.reason}`)
		end
	else
		const compiled = pipeline.compileText(case.text, case.name, pipeline.loadFile)

		if compiled.ok then
			failures += 1
			print(`FAIL  {case.name}: the stages accept it; expected a refusal with {case.reason}`)
		else
			const message = compiled.message or ""

			if string.find(message, case.reason, 1, true) ~= nil then
				passes += 1
				print(`PASS  {case.name}: {compiled.stage} refuses it: {message}`)
			else
				failures += 1
				print(`FAIL  {case.name}: {compiled.stage} refuses it with "{message}", the case expects "{case.reason}"`)
			end
		end
	end
end

print(`{passes} of {passes + failures} refusals agree ({readerRefusals} refused by the host reader, not the stages)`)

if failures > 0 then
	error(`{failures} refusals differ`, 0)
end
