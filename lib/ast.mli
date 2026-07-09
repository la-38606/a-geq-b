(** Abstract syntax for parsed inequalities.

    The parser produces a {!claim}; the normalizer turns a claim into the target
    polynomial. This module only defines the tree shape and has no dependency on
    {!Polynomial}, keeping syntax and algebra separate. *)

type expr =
  | Const of Rational.t (** a rational literal, e.g. [3] or [1/2] *)
  | Var of string (** a variable, e.g. ["a"], ["x1"] *)
  | Neg of expr (** unary minus *)
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | Div of expr * expr (** division; cleared of denominators by the normalizer *)
  | Pow of expr * int (** power with a nonnegative integer exponent *)

(** Relational operator of a claim. *)
type relop =
  | Ge (** [>=] *)
  | Le (** [<=] *)

(** A claim [lhs op rhs], e.g. [a^2 + b^2 >= 2*a*b]. *)
type claim =
  { lhs : expr
  ; op : relop
  ; rhs : expr
  }

(** [int n] is the literal [n]. *)
val int : int -> expr

(** [var name] is the variable [name]. *)
val var : string -> expr
