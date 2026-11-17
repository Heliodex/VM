--!strict
-- CODES AND THE DECODER
--
-- δ cannot copy δ (Lemma 3 of Lafont's paper), so a net with δ cells in it cannot be duplicated by a δ fan. A code is the same net with its δ cells taken out, which δ can copy, and the decoder puts them back.
--
-- γ copies δ just as δ copies γ: a δ cell meeting the root of a γ tree commutes down it and leaves one copy of itself at every leaf, with the copies' auxiliaries gathered by two more γ trees of the same shape. So the code keeps every δ port of the original net at a leaf of one of three γ trees, one for the principals, one for the first auxiliaries and one for the second. The decoder holds a single δ cell, and meeting the code plugs that cell into the three roots, which grows it back into all n of the original cells.
--
--   const Codes = require "./codes"
--
--   const b = B.new()
--   const code = Codes.encode(b, net)       -- no δ in it
--   const decoder = Codes.decoder(b, #Codes.freePorts(net))
--   b:wire(code, decoder.principal)         -- reduces to `net`, its free ports at decoder.ports
--
-- The code's root is a multiplexer whose ports are the original net's free ports, in the order freePorts lists them, followed by the three tree roots. The decoder is the dual multiplexer, so the two cancel and leave every port where it belongs.
-- The net to encode must be cut-free, since the code is meant to sit unreduced until it is decoded.

const B = require "./builder"
const G = require "./gadgets"
const Net = require "./net"
const Types = require "./types"

type Builder = B.Builder
type Fragment = Types.Fragment
type Net = Types.Net
type Port = Types.Port

-- The free ports of a net, in port order. A port is free when its cell is alive and nothing is wired to it.
const function freePorts(
	net: Net
): { Port }
	const ports: { Port } = {}

	for _, c in Net.liveCells(net) do
		for slot = 1, Net.portCount(net.Tag[c]) do
			const p = Net.port(c, slot)

			if net.Link[p] == 0 then
				table.insert(ports, p)
	end end end

	table.sort(ports)

	return ports
end

-- A γ tree with n leaves hung from the port `root`, returning the leaves. Mirrored trees take their leaves in the opposite order, which is what a tree of the other orientation cancels against.
-- With no leaves the tree is a lone eraser, which erases the decoder's δ cell. With one leaf there is no cell at all, and `root` is the leaf.
const function tree(
	b: Builder,
	root: Port,
	n: number,
	mirrored: boolean
): { Port }
	if n == 0 then
		b:wire(root, b:epsilon().principal)

		return {}
	end

	if n == 1 then
		return {
			root,
		}
	end

	const t =
		if mirrored then
			G.dualMultiplexer(b, n)
		else
			G.multiplexer(b, n)
	b:wire(root, t.principal)

	return t.ports
end

-- The code of `net`, built into `b`. Returns the code's root, its only free port.
const function encode(
	b: Builder,
	net: Net
): Port
	const cells = Net.liveCells(net)
	const free = freePorts(net)
	const deltas = {}

	for _, c in cells do
		const tag = net.Tag[c]

		if tag == Net.DELTA then
			table.insert(deltas, c)
		end

		for slot = 1, Net.portCount(tag) do
			const p = Net.port(c, slot)
			const q = net.Link[p]

			if q ~= 0 and Net.isPrincipal(p) and Net.isPrincipal(q) then
				error "only a cut-free net can be encoded"
	end end end

	const root = G.multiplexer(b, #free + 3)
	const n = #deltas
	const principals = tree(b, root.ports[#free + 1], n, false)
	const firsts = tree(b, root.ports[#free + 2], n, true)
	const seconds = tree(b, root.ports[#free + 3], n, true)
	-- where each port of the original ends up in the code: a copy of its cell, or a leaf if its cell is a δ
	const at: {
		[Port]: Port,
	} = {}

	for i, c in deltas do
		at[Net.principal(c)] = principals[i]
		at[Net.aux1(c)] = firsts[i]
		at[Net.aux2(c)] = seconds[i]
	end

	for _, c in cells do
		const tag = net.Tag[c]

		if tag == Net.DELTA then
			continue
		end

		const copy = Net.alloc(b.net, tag)

		for slot = 1, Net.portCount(tag) do
			at[Net.port(c, slot)] = Net.port(copy, slot)
	end end

	for i, p in free do
		b:wire(at[p], root.ports[i])
	end

	for p, q in net.Link do
		if q ~= 0 and p < q and at[p] then
			b:wire(at[p], at[q])
	end end

	return root.principal
end

-- The decoder for codes of nets with `arity` free ports. Its principal port is to meet a code's root, and its ports are where the decoded net's free ports come out.
const function decoder(
	b: Builder,
	arity: number
): Fragment
	const mux = G.dualMultiplexer(b, arity + 3)
	const d = b:delta()
	b:wire(mux.ports[arity + 1], d.principal)
	b:wire(mux.ports[arity + 2], d.aux1)
	b:wire(mux.ports[arity + 3], d.aux2)
	const ports: { Port } = {}

	for i = 1, arity do
		ports[i] = mux.ports[i]
	end

	return {
		principal = mux.principal,
		ports = ports,
	}
end

-- Whether a net has any δ cell in it.
const function hasDelta(
	net: Net
): boolean
	for _, c in Net.liveCells(net) do
		if net.Tag[c] == Net.DELTA then
			return true
	end end

	return false
end

return {
	freePorts = freePorts,
	encode = encode,
	decoder = decoder,
	hasDelta = hasDelta,
}
