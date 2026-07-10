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

(** Relation allowed in a side condition (equalities are allowed here, unlike in
    the claim itself). *)
type hyp_op =
  | Hyp_ge (** [>=] *)
  | Hyp_le (** [<=] *)
  | Hyp_eq (** [=] *)

(** A side condition constraining the domain, e.g. [a >= 0] or [a + b + c = 1]. *)
type hyp =
  { hyp_lhs : expr
  ; hyp_op : hyp_op
  ; hyp_rhs : expr
  }

(** A claim [lhs op rhs], e.g. [a^2 + b^2 >= 2*a*b], with optional side
    conditions introduced by ["given"] (empty when unconstrained). *)
type claim =
  { lhs : expr
  ; op : relop
  ; rhs : expr
  ; hyps : hyp list
  }

(** [int n] is the literal [n]. *)
val int : int -> expr

(** [var name] is the variable [name]. *)
val var : string -> expr
