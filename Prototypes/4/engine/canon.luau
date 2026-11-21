--!strict
-- COMPARING NETS WITHOUT CARING HOW THEIR CELLS ARE NUMBERED
--
-- Cell ids are recycled during reduction, so two equal results usually have completely different ids. Two tools here get around that.
-- Colour refinement gives every cell a colour that depends only on what it is wired to, which is how the fingerprint and the diagram placer tell cells apart. It is not a canonical form: two different nets can end up with the same colours.
-- Isomorphism is the exact check: whether two nets are the same up to renaming of cells.

local Net = require "./net"
local Types = require "./types"

type Cell = Types.Cell
type Net = Types.Net

-- Colour refinement: every cell starts with the colour of its symbol. Each round, `label` describes one cell from its own colour and the colours of what it is wired to, and cells with the same description are given the same new colour. Stop when a round changes nothing.
-- Labels are renamed to short numbers each round, since a label names the labels it was built from and would otherwise double in length every round.
const function refine(
	net: Net,
	cells: { Cell },
	label:
		(Cell, {
			[Cell]: string,
		}) -> string
): {
	[Cell]: string,
}
	local colour: {
		[Cell]: string,
	} = {}

	for _, c in cells do
		colour[c] = net.Tag[c]
	end

	for _ = 1, #cells do
		const raw: {
			[Cell]: string,
		} = {}

		for _, c in cells do
			raw[c] = label(c, colour)
		end

		const next: {
			[Cell]: string,
		} = {}
		const ids: {
			[string]: string,
		} = {}
		local count = 0
		local changed = false

		for _, c in cells do
			local id = ids[raw[c]]

			if not id then
				count += 1
				id = tostring(count)
				ids[raw[c]] = id
			end

			next[c] = id

			if id ~= colour[c] then
				changed = true
			end
		end

		colour = next

		if not changed then
			break
		end
	end

	return colour
end

-- Colour refinement that looks only at port kinds: principal or auxiliary, free or wired, and for a wire, the kind of port at its far end and that partner's colour. This is what the diagram placer uses to find cells that the drawing can swap.
const function refineKinds(net: Net, cells: { Cell }): {
	[Cell]: string,
}
	return refine(
		net,
		cells,
		function(
			c: Cell,
			colour: {
				[Cell]: string,
			}
		): string
			const parts: { string } = {}

			for slot = 1, Net.portCount(net.Tag[c]) do
				const mine =
					if slot == 1 then
						"P"
					else
						"A"
				const q = net.Link[Net.port(c, slot)] or 0

				if q == 0 then
					table.insert(parts, `{mine}free`)
				else
					const theirs =
						if Net.isPrincipal(q) then
							"P"
						else
							"A"
					table.insert(parts, `{mine}{theirs}{colour[Net.owner(q)]}`)
				end
			end

			table.sort(parts)

			return `{net.Tag[c]}({table.concat(parts, ",")})`
		end
	)
end

-- Same net up to renaming of cells. Cell ids are recycled during reduction, so two equal results usually have completely different ids.
-- One net's cells are walked in the order its wires visit them, and each is committed to a cell of the other, checking as it goes that every wire whose far end is already committed agrees.
-- Checking only once the whole renaming is built would try every renaming of the net before rejecting any of them, which is hopeless once more than a dozen cells share a symbol.
const function isomorphic(a: Net, b: Net): boolean
	const left, right = Net.liveCells(a), Net.liveCells(b)

	if #left ~= #right then
		return false
	end

	-- Walk the cells in the order the wires lead from one to the next, in each connected part in turn, so that a cell is almost always reached after a neighbour of it has been committed.
	const order: { Cell } = {}
	const walked: {
		[Cell]: boolean,
	} = {}

	for _, seed in left do
		if walked[seed] then
			continue
		end

		walked[seed] = true
		const queue: { Cell } = {
			seed,
		}
		local head = 1

		while head <= #queue do
			const c = queue[head]
			head += 1
			table.insert(order, c)

			for slot = 1, Net.STRIDE do
				const q = a.Link[(c - 1) * Net.STRIDE + slot] or 0

				if q ~= 0 then
					const near = Net.owner(q)

					if near ~= c and not walked[near] then
						walked[near] = true
						table.insert(queue, near)
					end
				end
			end
		end
	end

	const map: {
		[Cell]: Cell,
	} = {}
	const back: {
		[Cell]: Cell,
	} = {}

	-- Whether the two cells agree everywhere their wires already reach a committed cell.
	-- A wire whose far end is not committed yet cannot be judged, but it will be judged from the other side when that end is committed.
	const function agrees(ca: Cell, cb: Cell): boolean
		const pa, pb = (ca - 1) * Net.STRIDE, (cb - 1) * Net.STRIDE

		for slot = 1, Net.STRIDE do
			const x, y = a.Link[pa + slot] or 0, b.Link[pb + slot] or 0
			const x0, y0 = x == 0, y == 0

			if x0 ~= y0 then
				return false
			end

			if x == 0 then
				continue
			end

			if (x - 1) % Net.STRIDE ~= (y - 1) % Net.STRIDE then
				return false
			end

			const there, here = Net.owner(x), Net.owner(y)
			const placed = map[there]

			if placed ~= nil and placed ~= here then
				return false
			end

			const claimed = back[here]

			if claimed ~= nil and claimed ~= there then
				return false
			end
		end

		return true
	end

	const function search(i: number): boolean
		if i > #order then
			return true
		end

		const ca = order[i]

		for _, cb in right do
			if back[cb] == nil and a.Tag[ca] == b.Tag[cb] and agrees(ca, cb) then
				map[ca], back[cb] = cb, ca

				if search(i + 1) then
					return true
				end

				map[ca], back[cb] = nil, nil
			end
		end

		return false
	end

	return search(1)
end

return {
	refine = refine,
	refineKinds = refineKinds,
	isomorphic = isomorphic,
}
