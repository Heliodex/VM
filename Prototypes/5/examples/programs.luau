--!strict
-- THE PROGRAMS
--
-- Programs of the kind the language is meant for, written in the text syntax with let for local names. They are longer than the examples, and each one checks a step of real work: an accumulator, building a list, sorting, scanning a list of character codes, deep equality with kind, evaluating a tree, and gcd.
--
-- Text has no string type, so a word is a list of character codes, and a space is 32.

const Reader = require "../interpreter/reader"
const VM = require "../interpreter/vm"

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
(let sum (fix (lam rec (lam acc (lam l (if (? l) acc (rec (+ acc (head l)) (tail l)))))))
  (sum 0 (list 1 2 3 4 5)))
]==],
		"15"
	),

	-- Reverse by pushing each element onto an accumulator.
	value(
		"reverse a list",
		[==[
(let rev (fix (lam rec (lam acc (lam l (if (? l) acc (rec [(head l) acc] (tail l)))))))
  (rev ~ (list 1 2 3)))
]==],
		"(3 2 1)"
	),

	value(
		"append two lists",
		[==[
(let append (fix (lam rec (lam a (lam b (if (? a) b [(head a) ((rec (tail a)) b)])))))
  (append (list 1 2) (list 3 4)))
]==],
		"(1 2 3 4)"
	),

	value(
		"insertion sort",
		[==[
(let insert (fix (lam rec (lam x (lam l (if (? l) [x ~] (if (< x (head l)) [x l] [(head l) ((rec x) (tail l))]))))))
  (let isort (fix (lam rec (lam l (if (? l) ~ ((insert (head l)) (rec (tail l)))))))
    (isort (list 3 1 2 5 4))))
]==],
		"(1 2 3 4 5)"
	),

	value(
		"count words in character codes",
		[==[
(let words (fix (lam rec (lam l (lam inw (lam n
     (if (? l) n
       (if (= (head l) 32)
           (rec (tail l) 0 n)
           (rec (tail l) 1 (+ n (- 1 inw))))))))))
  (words (list 104 105 32 116 104 101 114 101 32 32 121 111 117) 0 0))
]==],
		"3"
	),

	value(
		"deep equality, equal lists",
		[==[
(let deq (fix (lam rec (lam (a b)
     (if (= (kind a) (kind b))
         (if (= (kind a) 2)
             (if ((rec (head a)) (head b)) ((rec (tail a)) (tail b)) 0)
             (if (= (kind a) 0) (= a b) (= (kind a) 1)))
         0))))
  (deq (list 1 (list 2 [3 ~]) 4) (list 1 (list 2 [3 ~]) 4)))
]==],
		"1"
	),

	value(
		"deep equality, lists that differ",
		[==[
(let deq (fix (lam rec (lam (a b)
     (if (= (kind a) (kind b))
         (if (= (kind a) 2)
             (if ((rec (head a)) (head b)) ((rec (tail a)) (tail b)) 0)
             (if (= (kind a) 0) (= a b) (= (kind a) 1)))
         0))))
  (deq (list 1 (list 2 3)) (list 1 (list 2 4))))
]==],
		"0"
	),

	-- A tree is [tag [left right]] for a sum or product, and [0 [n ~]] for a number.
	value(
		"evaluate an expression tree",
		[==[
(let ev (fix (lam rec (lam t
     (if (= (head t) 0) (head (tail t))
     (if (= (head t) 1) (+ (rec (head (tail t))) (rec (tail (tail t))))
         (* (rec (head (tail t))) (rec (tail (tail t)))))))))
  (ev [2 [[1 [[0 [3 ~]] [0 [4 ~]]]] [0 [2 ~]]]]))
]==],
		"14"
	),

	value(
		"gcd by subtraction",
		[==[
(let gcd (fix (lam rec (lam a (lam b
     (if (= a b) a (if (< a b) ((rec a) (- b a)) ((rec (- a b)) b)))))))
  (gcd 48 18))
]==],
		"6"
	),
}

return {
	examples = examples,
}
