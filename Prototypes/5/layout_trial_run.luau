--!strict
-- THE INDENTATION TRIAL
--
-- Lays out L2/trial/records.l2 (indented) and checks that the parser gives the same tree as for L2/trial/records.prog, the same code bracketed. Positions are left out of the comparison, since the two texts have different lines. It also counts the lines and the closing brackets of each text, which is what the trial measures.
--
--   lute run layout_trial_run.luau      (from Prototypes/5)

const Parser = require "./L2/parser"
const Layout = require "./L2/layout"
const fs = require "@lute/fs"

local function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)
	return text
end

-- Whether two trees are the same, ignoring the position of each node.
local function same(a: any, b: any, path: string): string?
	if type(a) ~= type(b) then
		return path .. ": " .. type(a) .. " against " .. type(b)
	end

	if type(a) ~= "table" then
		if a ~= b then
			return path .. ": " .. tostring(a) .. " against " .. tostring(b)
		end

		return nil
	end

	for k, v in a do
		if k ~= "at" and k ~= "line" and k ~= "col" then
			const diff = same(v, b[k], path .. "." .. tostring(k))

			if diff ~= nil then
				return diff
			end
		end
	end

	for k, _ in b do
		if k ~= "at" and k ~= "line" and k ~= "col" and a[k] == nil then
			return path .. "." .. tostring(k) .. ": missing on the left"
		end
	end

	return nil
end

local function closers(text: string): number
	local n = 0

	for _ in string.gmatch(text, "%)") do
		n += 1
	end

	return n
end

const indented = readFile("L2/trial/records.l2")
const bracketed = readFile("L2/trial/records.prog")
const laid = Layout.layout(indented)

print(string.format("source: indented %d lines, %d closing brackets; bracketed %d lines, %d closing brackets",
	select(2, string.gsub(indented, "\n", "\n")), closers(indented),
	select(2, string.gsub(bracketed, "\n", "\n")), closers(bracketed)))
print(string.format("laid out: %d lines, %d closing brackets", select(2, string.gsub(laid, "\n", "\n")), closers(laid)))

const okA, treeA = pcall(Parser.parse, laid)
const okB, treeB = pcall(Parser.parse, bracketed)

if not okA then
	print("FAIL the laid-out text does not parse: " .. tostring(treeA))
elseif not okB then
	print("FAIL the bracketed text does not parse: " .. tostring(treeB))
else
	const diff = same(treeA, treeB, "program")

	if diff == nil then
		print("PASS the indented and bracketed forms give the same tree")
	else
		print("FAIL the trees differ at " .. diff)
	end
end
