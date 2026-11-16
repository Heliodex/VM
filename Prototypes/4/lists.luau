--!strict
-- LISTS (SCOTT ENCODING)
--
-- A list is consumed by applying it to a handler for each case: the cons case takes the head and the tail, and the nil case takes nothing.
--   nil         = λc.λn. n
--   cons h t    = λc.λn. c h t
-- Every argument here is used at most once, so no list operation needs `share`, and the sharing residue that numerals suffer from does not arise.
--
-- Scott's nil is the same function as `false` (see booleans.luau), so `isNil` cannot tell them apart, and it reads the empty list and `false` alike. This ambiguity is accepted for now.
--
-- A list is read back one cell at a time: `isNil` says whether it is empty, and `head` and `tail` take it apart. Lists have no whole-value readback yet.

const Bo = require "./booleans"
const B = require "./builder"
const L = require "./lambda"
const Types = require "./types"

type Builder = B.Builder
type Port = Types.Port

-- λc.λn. n
const function nilValue(
	b: Builder
): Port
	return L.lam(
		b, function(
			_c: Port
		): Port
			return L.lam(
				b, function(
					n: Port
				): Port
					return n
				end
			)
		end
	)
end

-- λh.λt.λc.λn. c h t
const function cons(
	b: Builder
): Port
	return L.lam(
		b, function(
			h: Port
		): Port
			return L.lam(
				b, function(
					t: Port
				): Port
					return L.lam(
						b, function(
							c: Port
						): Port
							return L.lam(
								b, function(
									_n: Port
								): Port
									return L.app(b, L.app(b, c, h), t)
								end
							)
						end
					)
				end
			)
		end
	)
end

-- λl.λd. l (λh.λt. h) d: the head of a list, or `d` for the empty list.
const function head(
	b: Builder
): Port
	return L.lam(
		b, function(
			l: Port
		): Port
			return L.lam(
				b, function(
					d: Port
				): Port
					const first = L.lam(
						b, function(
							h: Port
						): Port
							return L.lam(
								b, function(
									_t: Port
								): Port
									return h
								end
							)
						end
					)

					return L.app(b, L.app(b, l, first), d)
				end
			)
		end
	)
end

-- λl.λd. l (λh.λt. t) d: the tail of a list, or `d` for the empty list.
const function tail(
	b: Builder
): Port
	return L.lam(
		b, function(
			l: Port
		): Port
			return L.lam(
				b, function(
					d: Port
				): Port
					const rest = L.lam(
						b, function(
							_h: Port
						): Port
							return L.lam(
								b, function(
									t: Port
								): Port
									return t
								end
							)
						end
					)

					return L.app(b, L.app(b, l, rest), d)
				end
			)
		end
	)
end

-- λl. l (λh.λt. false) true
const function isNil(
	b: Builder
): Port
	return L.lam(
		b, function(
			l: Port
		): Port
			const notEmpty = L.lam(
				b, function(
					_h: Port
				): Port
					return L.lam(
						b, function(
							_t: Port
						): Port
							return Bo.boolean(b, false)
						end
					)
				end
			)

			return L.app(b, L.app(b, l, notEmpty), Bo.boolean(b, true))
		end
	)
end

return {
	nilValue = nilValue,
	cons = cons,
	head = head,
	tail = tail,
	isNil = isNil,
}
