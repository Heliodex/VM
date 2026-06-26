--!strict

-- A program is a list of functions.
export type ToParse = {
	read src: { string },
	pos: number,
}

local function current(p: ToParse): string?
	if p.pos > #p.src then
		return nil
	end

	return p.src[p.pos]
end

local function advance(p: ToParse)
	p.pos += 1
end

local function toParse(src: string): ToParse
	return {
		src = string.split(src, ""),
		pos = 1,
	}
end

return {
	current = current,
	advance = advance,
	toParse = toParse,
}
