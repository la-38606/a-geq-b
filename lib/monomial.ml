(** Monomials as exponent vectors.

    A monomial such as [a^2 * b * c^3] is stored as its vector of exponents,
    indexed by variable position:

    {[ [2; 1; 3]   (* a^2 b^1 c^3, with variable order a, b, c *) ]}

    {2 Canonical form}

    To make monomials a good [Map] key with a single, unambiguous
    representation, we require the exponent vector to have {b no trailing
    zeros}.  Consequences:

    - the constant monomial (all exponents zero) is the empty list [[]];
    - [a^2] is [[2]] whether the ambient polynomial has 1, 3 or 10 variables;
    - [a * c] (with order a,b,c) is [[1; 0; 1]] — interior zeros are kept, only
      trailing zeros are dropped.

    Every value produced by this module is canonical.  Exponents are always
    nonnegative; [canonical] enforces this. *)

type t = int list

(* Strip trailing zeros from a reversed list, then reverse back. *)
let rec drop_leading_zeros = function
  | 0 :: rest -> drop_leading_zeros rest
  | l -> l

(** Put an arbitrary exponent vector into canonical form (validate
    nonnegativity, drop trailing zeros). *)
let canonical (m : t) : t =
  List.iter
    (fun e -> if e < 0 then invalid_arg "Monomial: negative exponent")
    m;
  List.rev (drop_leading_zeros (List.rev m))

(** The constant monomial [1]. *)
let one : t = []

(** [var i] is the monomial for the [i]-th variable (0-indexed), i.e. [x_i^1]. *)
let var (i : int) : t =
  if i < 0 then invalid_arg "Monomial.var: negative index";
  List.init (i + 1) (fun j -> if j = i then 1 else 0)

let is_constant (m : t) : bool = m = []

(** Total degree: the sum of all exponents. *)
let degree (m : t) : int = List.fold_left ( + ) 0 m

(** Multiplication adds exponent vectors position-wise, padding the shorter
    vector with zeros.  The result is canonical. *)
let mul (a : t) (b : t) : t =
  let rec go a b =
    match a, b with
    | [], ys -> ys
    | xs, [] -> xs
    | x :: xs, y :: ys -> (x + y) :: go xs ys
  in
  (* Both inputs are assumed canonical, so their sum has no trailing zeros;
     [canonical] is applied anyway to stay robust against hand-built inputs. *)
  canonical (go a b)

(** Total order on monomials: lexicographic on exponent vectors, treating a
    missing tail as zeros (so it is consistent regardless of length).  This is
    the ordering used to key polynomials, and it also gives a deterministic
    print order.  For canonical monomials, [compare m1 m2 = 0] iff [m1 = m2]. *)
let compare (a : t) (b : t) : int =
  let rec go a b =
    match a, b with
    | [], [] -> 0
    | [], y :: ys -> let c = Int.compare 0 y in if c <> 0 then c else go [] ys
    | x :: xs, [] -> let c = Int.compare x 0 in if c <> 0 then c else go xs []
    | x :: xs, y :: ys -> let c = Int.compare x y in if c <> 0 then c else go xs ys
  in
  go a b

let equal (a : t) (b : t) : bool = compare a b = 0
