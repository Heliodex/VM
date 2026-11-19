--!strict
-- THE PROGRAMS
--
-- Programs of the kind the language is meant for, written in the text syntax with letrec for recursive functions. They are longer than the examples, and each one checks a step of real work: an accumulator, building a list, sorting, scanning a list of character codes, deep equality with kind, evaluating a tree, and gcd.
--
-- Text has no string type, so a word is a list of character codes, and a space is 32.

const Reader = require "../reader"
const VM = require "../../interpreter/vm"

type Example = {
	name: string,
	program: VM.Expr,
	fuel: number,
	outcome: string,
	expect: string?,
}

const FUEL = 1e6

const function value(
	name: string,
	source: string,
	expect: string
): Example
	return {
		name = name,
		program = Reader.parse(source),
		fuel = FUEL,
		outcome = "value",
		expect = expect,
	}
end

const examples: { Example } = {
	-- Sum with an accumulator: the recursive call carries the total so far.
	value(
		"sum with an accumulator",
		[==[
(letrec sum (fn (acc l) (if (? l) acc (sum (+ acc (head l)) (tail l))))
  (sum 0 (list 1 2 3 4 5)))
]==],
		"15"
	),

	-- Reverse by pushing each element onto an accumulator.
	value(
		"reverse a list",
		[==[
(letrec rev (fn (acc l) (if (? l) acc (rev [(head l) acc] (tail l))))
  (rev ~ (list 1 2 3)))
]==],
		"(3 2 1)"
	),

	value(
		"append two lists",
		[==[
(letrec append (fn (a b) (if (? a) b [(head a) (append (tail a) b)]))
  (append (list 1 2) (list 3 4)))
]==],
		"(1 2 3 4)"
	),

	value(
		"insertion sort",
		[==[
(letrec insert (fn (x l) (if (? l) [x ~] (if (< x (head l)) [x l] [(head l) (insert x (tail l))])))
  (letrec isort (fn l (if (? l) ~ (insert (head l) (isort (tail l)))))
    (isort (list 3 1 2 5 4))))
]==],
		"(1 2 3 4 5)"
	),

	value(
		"count words in character codes",
		[==[
(letrec words (fn (l inw n)
     (if (? l) n
       (if (= (head l) 32)
           (words (tail l) 0 n)
           (words (tail l) 1 (+ n (- 1 inw))))))
  (words (list 104 105 32 116 104 101 114 101 32 32 121 111 117) 0 0))
]==],
		"3"
	),

	value(
		"deep equality, equal lists",
		[==[
(letrec deq (fn (a b)
     (if (= (kind a) (kind b))
         (if (= (kind a) 2)
             (if (deq (head a) (head b)) (deq (tail a) (tail b)) 0)
             (if (= (kind a) 0) (= a b) (= (kind a) 1)))
         0))
  (deq (list 1 (list 2 [3 ~]) 4) (list 1 (list 2 [3 ~]) 4)))
]==],
		"1"
	),

	value(
		"deep equality, lists that differ",
		[==[
(letrec deq (fn (a b)
     (if (= (kind a) (kind b))
         (if (= (kind a) 2)
             (if (deq (head a) (head b)) (deq (tail a) (tail b)) 0)
             (if (= (kind a) 0) (= a b) (= (kind a) 1)))
         0))
  (deq (list 1 (list 2 3)) (list 1 (list 2 4))))
]==],
		"0"
	),

	-- A tree is [tag [left right]] for a sum or product, and [0 [n ~]] for a number.
	value(
		"evaluate an expression tree",
		[==[
(letrec ev (fn t
     (if (= (head t) 0) (head (tail t))
     (if (= (head t) 1) (+ (ev (head (tail t))) (ev (tail (tail t))))
         (* (ev (head (tail t))) (ev (tail (tail t)))))))
  (ev [2 [[1 [[0 [3 ~]] [0 [4 ~]]]] [0 [2 ~]]]]))
]==],
		"14"
	),

	value(
		"gcd by subtraction",
		[==[
(letrec gcd (fn (a b)
     (if (= a b) a (if (< a b) (gcd a (- b a)) (gcd (- a b) b))))
  (gcd 48 18))
]==],
		"6"
	),
}

return {
	examples = examples,
}
