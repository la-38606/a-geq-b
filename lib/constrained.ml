(** Positivstellensatz certificates for {i constrained} inequalities.

    An unconstrained certificate ({!Certificate}) proves [p >= 0] everywhere by
    writing [p] as a sum of squares.  Many olympiad inequalities instead hold
    only on a region cut out by hypotheses — [a >= 0], [a + b + c = 1],
    [abc = 1], … .  There we prove [p >= 0] on

    {[ { x | g_1(x) >= 0, …, h_1(x) = 0, … } ]}

    with a certificate of the Positivstellensatz shape

    {[ p = sigma_0 + sum_i sigma_i * g_i + sum_j lambda_j * h_j ]}

    where each [sigma] is a sum of squares (so [>= 0]) and each [lambda_j] is an
    arbitrary polynomial.  On the feasible set every [g_i >= 0] and every
    [h_j = 0], so [sigma_i g_i >= 0] and [lambda_j h_j = 0]; hence [p >= 0]
    there.  This module holds the {i data}; the trusted {!Checker} decides
    whether the claimed identity and sign conditions actually hold. *)

(** A hypothesis constraining the domain. *)
type hypothesis =
  | Nonneg of Polynomial.t (** [g >= 0] *)
  | Zero of Polynomial.t (** [h = 0] *)

(** One product term of the certificate.  Its kind is matched to the kind of
    hypothesis it may use, so the two cannot be confused. *)
type product =
  | Times_nonneg of
      { multiplier : Certificate.t (** an SOS [sigma], hence [>= 0] *)
      ; nonneg : Polynomial.t (** the [Nonneg] hypothesis [g] it scales *)
      } (** contributes [sigma * g], which is [>= 0] on the domain *)
  | Times_zero of
      { multiplier : Polynomial.t (** any polynomial [lambda] *)
      ; zero : Polynomial.t (** the [Zero] hypothesis [h] it scales *)
      } (** contributes [lambda * h], which is [0] on the domain *)

(** A certificate that [p >= 0] on the set cut out by the hypotheses:
    [p = base + sum (sigma_i * g_i) + sum (lambda_j * h_j)].  [base] and every
    {!Times_nonneg} multiplier are sums of squares. *)
type t =
  { base : Certificate.t (** the unconstrained SOS part [sigma_0] *)
  ; products : product list
  }

let nonneg (g : Polynomial.t) : hypothesis = Nonneg g
let zero (h : Polynomial.t) : hypothesis = Zero h

let times_nonneg ~(multiplier : Certificate.t) ~(nonneg : Polynomial.t) : product =
  Times_nonneg { multiplier; nonneg }
;;

let times_zero ~(multiplier : Polynomial.t) ~(zero : Polynomial.t) : product =
  Times_zero { multiplier; zero }
;;

let make ~(base : Certificate.t) ~(products : product list) : t = { base; products }

(* --- rendering ---------------------------------------------------------- *)

let string_of_hypothesis (vars : Pretty.vars) : hypothesis -> string = function
  | Nonneg g -> Printf.sprintf "%s >= 0" (Pretty.string_of_poly vars g)
  | Zero h -> Printf.sprintf "%s = 0" (Pretty.string_of_poly vars h)
;;

let string_of_product (vars : Pretty.vars) : product -> string = function
  | Times_nonneg { multiplier; nonneg } ->
    Printf.sprintf
      "(%s)*(%s)"
      (Certificate.to_string vars multiplier)
      (Pretty.string_of_poly vars nonneg)
  | Times_zero { multiplier; zero } ->
    Printf.sprintf
      "(%s)*(%s)"
      (Pretty.string_of_poly vars multiplier)
      (Pretty.string_of_poly vars zero)
;;

(** Render the certificate's right-hand side [base + sum products]. *)
let to_string (vars : Pretty.vars) (cert : t) : string =
  let parts =
    (match cert.base with
     | [] -> []
     | base -> [ Certificate.to_string vars base ])
    @ List.map (string_of_product vars) cert.products
  in
  match parts with
  | [] -> "0"
  | _ -> String.concat " + " parts
;;
