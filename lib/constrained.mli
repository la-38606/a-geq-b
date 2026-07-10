(** Positivstellensatz certificates for {i constrained} inequalities.

    Where {!Certificate} proves [p >= 0] everywhere by a sum of squares, this
    proves [p >= 0] only on the region cut out by hypotheses [g_i >= 0] and
    [h_j = 0], via a certificate of the shape

    {[ p = base + sum_i sigma_i * g_i + sum_j lambda_j * h_j ]}

    with each [base]/[sigma_i] a sum of squares and each [lambda_j] arbitrary.
    This module holds the data only; the trusted {!Checker} verifies the
    identity and the sign conditions. *)

(** A hypothesis constraining the domain. *)
type hypothesis =
  | Nonneg of Polynomial.t (** [g >= 0] *)
  | Zero of Polynomial.t (** [h = 0] *)

(** One product term, its kind matched to the hypothesis kind it may use. *)
type product =
  | Times_nonneg of
      { multiplier : Certificate.t (** an SOS [sigma >= 0] *)
      ; nonneg : Polynomial.t (** the [Nonneg] hypothesis it scales *)
      }
  | Times_zero of
      { multiplier : Polynomial.t (** any polynomial [lambda] *)
      ; zero : Polynomial.t (** the [Zero] hypothesis it scales *)
      }

(** [p = base + sum products], with [base] and every {!Times_nonneg} multiplier
    a sum of squares. *)
type t =
  { base : Certificate.t
  ; products : product list
  }

val nonneg : Polynomial.t -> hypothesis
val zero : Polynomial.t -> hypothesis
val times_nonneg : multiplier:Certificate.t -> nonneg:Polynomial.t -> product
val times_zero : multiplier:Polynomial.t -> zero:Polynomial.t -> product
val make : base:Certificate.t -> products:product list -> t

(** ["g >= 0"] or ["h = 0"]. *)
val string_of_hypothesis : Pretty.vars -> hypothesis -> string

(** Render the certificate's right-hand side [base + sum products]. *)
val to_string : Pretty.vars -> t -> string
