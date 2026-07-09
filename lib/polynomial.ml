(** Multivariate polynomials over the rationals.

    A polynomial is a finite map from {!Monomial.t} to nonzero
    {!Rational.t} coefficients.

    {2 Canonical form / invariant}

    A value of type {!t} is always in canonical form:

    - every key is a canonical monomial (see {!Monomial});
    - {b no key maps to a zero coefficient} (zero terms are dropped);
    - like terms are combined (guaranteed by using a map keyed on monomials).

    All constructors and operations below preserve this invariant, so
    {!equal} can be plain structural equality of the maps: two polynomials are
    equal iff they have the same canonical normal form.  This is exactly the
    property the certificate checker relies on. *)

module M = Map.Make (Monomial)

type t = Rational.t M.t

(* --- internal helper ---------------------------------------------------- *)

(* Add coefficient [c] onto monomial [m] in [p], dropping the entry if the
   resulting coefficient is zero.  Preserves the no-zero-coefficient invariant. *)
let add_coeff (m : Monomial.t) (c : Rational.t) (p : t) : t =
  M.update
    m
    (fun cur ->
       let s =
         match cur with
         | None -> c
         | Some x -> Rational.add x c
       in
       if Rational.is_zero s then None else Some s)
    p
;;

(* --- constructors ------------------------------------------------------- *)

let zero : t = M.empty

(** The constant polynomial [c].  Yields {!zero} when [c] is zero. *)
let const (c : Rational.t) : t =
  if Rational.is_zero c then zero else M.singleton Monomial.one c
;;

let one : t = const Rational.one
let of_int (n : int) : t = const (Rational.of_int n)

(** [var i] is the polynomial equal to the [i]-th variable. *)
let var (i : int) : t = M.singleton (Monomial.var i) Rational.one

(** [monomial m c] is the single-term polynomial [c * m]. *)
let monomial (m : Monomial.t) (c : Rational.t) : t =
  if Rational.is_zero c then zero else M.singleton (Monomial.canonical m) c
;;

(* --- queries ------------------------------------------------------------ *)

let is_zero (p : t) : bool = M.is_empty p

(** Coefficient of monomial [m] in [p] (zero if absent). *)
let coeff (m : Monomial.t) (p : t) : Rational.t =
  match M.find_opt (Monomial.canonical m) p with
  | Some c -> c
  | None -> Rational.zero
;;

(** Total degree of [p]; the zero polynomial has degree 0 by convention. *)
let degree (p : t) : int = M.fold (fun m _ acc -> max acc (Monomial.degree m)) p 0

(** Number of variables actually mentioned (index of the highest-used variable
    plus one); 0 for a constant. *)
let num_vars (p : t) : int = M.fold (fun m _ acc -> max acc (List.length m)) p 0

(** Terms as an association list, sorted by {!Monomial.compare}. *)
let to_list (p : t) : (Monomial.t * Rational.t) list = M.bindings p

(* --- arithmetic --------------------------------------------------------- *)

let add (p : t) (q : t) : t =
  M.union
    (fun _ a b ->
       let s = Rational.add a b in
       if Rational.is_zero s then None else Some s)
    p
    q
;;

let neg (p : t) : t = M.map Rational.neg p
let sub (p : t) (q : t) : t = add p (neg q)

(** Multiply every coefficient by the scalar [c]. *)
let scalar_mul (c : Rational.t) (p : t) : t =
  if Rational.is_zero c then zero else M.map (Rational.mul c) p
;;

let mul (p : t) (q : t) : t =
  M.fold
    (fun m1 c1 acc ->
       M.fold
         (fun m2 c2 acc -> add_coeff (Monomial.mul m1 m2) (Rational.mul c1 c2) acc)
         q
         acc)
    p
    zero
;;

(** [pow p n] raises [p] to the nonnegative integer power [n]; [pow p 0 = one]. *)
let rec pow (p : t) (n : int) : t =
  if n < 0
  then invalid_arg "Polynomial.pow: negative exponent"
  else if n = 0
  then one
  else mul p (pow p (n - 1))
;;

(** Sum of a list of polynomials. *)
let sum (ps : t list) : t = List.fold_left add zero ps

(* --- normalisation & equality ------------------------------------------ *)

(** Re-establish the canonical invariant for a possibly hand-built map:
    canonicalise every key and drop zero coefficients.  For values produced by
    the constructors above this is the identity. *)
let normalize (p : t) : t =
  M.fold
    (fun m c acc ->
       if Rational.is_zero c then acc else add_coeff (Monomial.canonical m) c acc)
    p
    zero
;;

(** Equality of canonical normal forms.  Independent of how each polynomial was
    built. *)
let equal (p : t) (q : t) : bool = M.equal Rational.equal p q
