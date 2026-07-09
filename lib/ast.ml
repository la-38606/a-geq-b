(** Abstract syntax for parsed inequalities.

    The parser (see {!Parser}) turns a string like
    ["prove a^2 + b^2 >= 2*a*b"] into a {!claim}.  The {!Normalizer} then turns
    a {!claim} into the polynomial [p = A - B] that we try to prove is [>= 0].

    This module is deliberately tiny: it only defines the tree shape.  It has no
    dependency on {!Polynomial}, keeping "syntax" and "algebra" separate. *)

type expr =
  | Const of Rational.t          (** a rational literal, e.g. [3] or [1/2] *)
  | Var of string                (** a variable, e.g. ["a"], ["x1"] *)
  | Neg of expr                  (** unary minus *)
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | Pow of expr * int            (** power with a nonnegative integer exponent *)

(** Relational operator of a claim. *)
type relop =
  | Ge  (** [>=] *)
  | Le  (** [<=] *)

(** A claim [lhs op rhs], e.g. [a^2 + b^2 >= 2*a*b]. *)
type claim = { lhs : expr; op : relop; rhs : expr }

(* --- small convenience constructors ------------------------------------- *)

let int (n : int) : expr = Const (Rational.of_int n)
let var (name : string) : expr = Var name
