--!strict
-- Types shared by main.luau (the reduction engine) and diagram.luau (the SVG
-- renderer). Requiring this module yields an empty table at runtime; the point
-- is the exported types.

export type Gamma = "Gamma"
export type Delta = "Delta"
export type Epsilon = "Epsilon"
export type Symbol = Gamma | Delta | Epsilon

export type Cell = number
export type Port = number

-- A net is completely described by:
--     a finite set X (of free ports),
--     a finite set C (of cells),
--     a symbol l(c) for each c ∈ C,
--     a finite set W (of wires),
--     a set δw of 0 or 2 ports for each w ∈ W.
-- We keep C and l in `Tag`, and fold W and X into the wiring array:
--   Link[p] == 0 means p is a free port (p ∈ X); otherwise Link[Link[p]] == p.
export type Net = {
	read Tag: { Symbol },
	read Link: { Port },
	read Active: { Port },
	read Free: { Cell },
}

return {}
