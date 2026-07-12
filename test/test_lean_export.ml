(** Tests for Lean proof emission (shape only; actual Lean-kernel acceptance is
    checked by building lean/Proofs.lean). *)

open A_geq_b

let vars = [ "a"; "b"; "c" ]

(* Substring test (Stdlib has no substring search). *)
let contains needle s =
  let nl = String.length needle
  and sl = String.length s in
  let rec go i =
    if i + nl > sl then false else if String.sub s i nl = needle then true else go (i + 1)
  in
  go 0
;;

let must out s =
  Alcotest.(check bool) (Printf.sprintf "output contains %S" s) true (contains s out)
;;

let test_hello_world () =
  let p = Prover.hello_world_target () in
  let cert = Prover.hello_world_certificate () in
  let out = Lean_export.theorem ~name:"aeqb" ~vars p cert in
  must out "import Mathlib";
  must out "theorem aeqb (a b c : \xe2\x84\x9d)";
  (* (a b c : ℝ) *)
  must out ":= by";
  must out "by ring";
  must out "rw [h]";
  must out "positivity";
  must out "(a - b)";
  (* a square base *)
  must out "1/2"
;;

(* its coefficient *)

let test_constant () =
  (* p = 3 (as from "5 >= 2"); no variables, so no binder. *)
  let three = Polynomial.of_int 3 in
  let cert = Certificate.make [ Certificate.term (Rational.of_int 3) Polynomial.one ] in
  let out = Lean_export.theorem ~name:"c" ~vars:[] three cert in
  must out "theorem c : (0 : \xe2\x84\x9d)";
  (* no binder *)
  Alcotest.(check bool) "no variable binder" false (contains "(a" out || contains "(x" out)
;;

let test_keyword_variable_sanitized () =
  (* A variable named like a Lean keyword must not appear as a binder; all
     variables are renamed to x1, x2, ... so the file still compiles. *)
  let a = Polynomial.var 0 in
  let p = Polynomial.mul a a in
  let cert = Certificate.make [ Certificate.term Rational.one a ] in
  let out = Lean_export.theorem ~name:"t" ~vars:[ "fun" ] p cert in
  must out "(x1 : \xe2\x84\x9d)";
  (* (x1 : ℝ) *)
  Alcotest.(check bool) "no Lean keyword leaks into the proof" false (contains "fun" out)
;;

let () =
  Alcotest.run
    "lean_export"
    [ ( "emit"
      , [ Alcotest.test_case "hello-world proof" `Quick test_hello_world
        ; Alcotest.test_case "constant, no binder" `Quick test_constant
        ; Alcotest.test_case
            "keyword variable sanitized"
            `Quick
            test_keyword_variable_sanitized
        ] )
    ]
;;
