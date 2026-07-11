(** Restrained terminal styling for the CLI.

    ANSI colour is emitted only to an interactive terminal with [NO_COLOR] unset,
    so redirected or captured output stays plain and machine-readable. *)

(** [true] iff colour should be emitted on standard output. *)
val colour : bool Lazy.t

(** Faint styling, for structural labels. *)
val label : string -> string

(** Positive-result styling (green). *)
val ok : string -> string

(** Failure / invalid-input styling (red). *)
val bad : string -> string

(** Indent every non-empty line of the argument by two spaces. *)
val indent : string -> string
