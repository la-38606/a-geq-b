(lang dune 3.0)

(name a-geq-b)

(package
 (name a-geq-b)
 (synopsis "A>=B: prove polynomial inequalities via sum-of-squares certificates")
 (description
  "A>=B (pronounced A-geq-B) proves polynomial inequalities A >= B by rewriting\n them as p = A - B >= 0 and verifying a sum-of-squares certificate\n p = sum_i c_i * q_i^2 with c_i >= 0, using exact rational arithmetic.")
 (depends ocaml dune zarith yojson alcotest))
