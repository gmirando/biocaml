(** FASTA files. The FASTA family of file formats has different
    incompatible descriptions
    ({{:https://www.proteomecommons.org/tranche/examples/proteomecommons-fasta/fasta.jsp
    }1}, {{:http://zhanglab.ccmb.med.umich.edu/FASTA/}2},
    {{:http://en.wikipedia.org/wiki/FASTA_format}3}, etc.). Roughly
    FASTA files are in the format:

    {v
    # comment
    # comment
    ...
    >header
    sequence
    >header
    sequence
    ...
    v}

    where the sequence may span multiple lines, and a ';' may be used
    instead of '#' to start comments.

    Header lines begin with the '>' character. It is often considered
    that all characters until the first whitespace define the {i name}
    of the content, and any characters beyond that define additional
    information in a format specific to the file provider.

    Sequence are most often a sequence of characters denoting
    nucleotides or amino acids. However, sometimes FASTA files provide
    quality scores, either as ASCII encoded, e.g. as supported by
    modules {!module: Biocaml_phred_score} and {!module:
    Biocaml_solexa_score}, or as space-separated integers.

    Thus, the FASTA format is really a family of formats with a fairly
    loose specification of the header and content formats. The only
    consistently followed meaning of the format is:

    - the file can begin with comment lines that begin with a '#' or
    ';' character and/or all white-space lines

    - the header lines begins with the '>' character, is followed
    optionally by whitespace, and then contains some string

    - each header line is followed by a sequence of characters or
    space-separated integers, often just one line but allowed to span
    multiple lines

    - and this alternating pair of header/sequence lines can occur
    repeatedly.

    Names used throughout this module use [sequence] to generically
    mean either kind of data found in the sequence lines, [char_seq]
    to mean specifically a sequence of characters, and [int_seq] to
    mean specifically a sequence of integers.

    Parsing functions throughout this module take the following
    optional arguments:

    - [filename] - used only for error messages when the data source
    is not the file.

    - [pedantic] - if true, which is the default, report more
    errors: Biocaml_transform.no_error lines, non standard
    characters.

    - [sharp_comments] and [semicolon_comments] - if true, allow
    comments beginning with a '#' or ';' character,
    respectively. Setting both to true is okay, although it is not
    recommended to have such files. Setting both to false implies that
    comments are disallowed.

*)

(** {2 Fasta Content Type Definitions } *)

type char_seq = string
(** A sequence of characters. *)

type int_seq = int list
(** A sequence of integer quality scores. *)

type 'a item = {
  header : string;
  sequence : 'a;
}
(** A named FASTA item. *)


type 'a raw_item = [
  | `comment of string
  | `header of string
  | `partial_sequence of 'a
]
(** Lowest level items parsed by this module:

    - [`comment _] - a single comment line without the final
      newline.

    - [`header _] - a single header line without the initial '>',
      whitespace following this, nor final newline.

    - [`partial_sequence _] - either a sequence of characters,
      represented as a string, or a sequence of space separated
      integers, represented by an [int list]. The value does not
      necessarily carry the complete content associated with a
      header. It may be only part of the sequence, which can be useful
      for files with large sequences (e.g. genomic sequence
      files).  *)

(** {2 Tags: Describe The Format } *)

module Tags: sig
  (** Additional format-information tags (c.f. {!Biocaml_tags}). *)


  type char_sequence = {
    impose_sequence_alphabet: char list option;
  }
  (** The format details for [char_seq] FASTA files. *)

  type common = {
    forbid_empty_lines: bool;
    only_header_comment: bool;
    sharp_comments: bool;
    semicolon_comments: bool;
    max_items_per_line: int option;
  }
  (** The format details for any kind of FASTA file. *)

  type t = {
    common: common;
    sequence: [ `int_sequence | `char_sequence of char_sequence ]
  }
  (** The tags describing as much information as possible a given
      FASTA “sub-format” *)


  val char_sequence_default: t
  (** The default tags (for [char_seq]). *)

  val int_sequence_default: t
  (** The default tags (for [int_seq]). *)

  val pedantic_with: t -> t
  (** For a given set of tags [base], add pedantry.  *)

  val is_char_sequence: t -> bool
  (** Test the value of [t.sequence]. *)

  val is_int_sequence: t -> bool
  (** Test the value of [t.sequence]. *)

  val to_string: t -> string
  (** Serialize tags (for now S-Expressions). *)

  val of_string: string -> (t, [> `tags_of_string of exn]) Core.Result.t
  (** Parse tags (for now S-Expressions). *)

  val t_of_sexp: Sexplib.Sexp.t -> t
  val sexp_of_t: t -> Sexplib.Sexp.t

end

(** {2 Error Types} *)

module Error : sig
  (** All errors generated by any function in the [Fasta] module
      are defined here. Type [t] is the union of all errors, and subsets
      of this are defined as needed to specify precise return types for
      various functions.

      - [`empty_line pos] - an empty line was found in a position [pos]
      where it is not allowed.

      - [`incomplete_input (lines,s)] - the input ended
      prematurely. Trailing contents, which cannot be used to fully
      construct an item, are provided: [lines] is the complete lines
      parsed and [s] is any final string not ending in a newline.

      - [`malformed_partial_sequence s] - indicates that [s] could not
      be parsed into a valid (partial) sequence value.

      - [`unnamed_char_seq x] - a [char_seq] value [x] was found without
      a preceding header section.

      - [`unnamed_int_seq x] - an [int_seq] value [x] was found without
      a preceding header section.

  *)

  type string_to_raw_item = [
  | `empty_line of Biocaml_pos.t
  | `incomplete_input of Biocaml_pos.t * string list * string option
  | `malformed_partial_sequence of string
  ]
  (** Errors raised when converting a string to a {!type: raw_item}. *)

  type t = [
  | string_to_raw_item
  | `unnamed_char_seq of char_seq
  | `unnamed_int_seq of int_seq
  ]
  (** Union of all errors. *)

  val sexp_of_string_to_raw_item : string_to_raw_item -> Sexplib.Sexp.t
  val string_to_raw_item_of_sexp : Sexplib.Sexp.t -> string_to_raw_item
  val sexp_of_t : t -> Sexplib.Sexp.t
  val t_of_sexp : Sexplib.Sexp.t -> t

end

(** {2 [In_channel] Functions } *)

exception Error of Error.t
(** The only exception raised by this module. *)

val in_channel_to_char_seq_item_stream :
  ?buffer_size:int ->
  ?filename:string ->
  ?tags:Tags.t ->
  in_channel ->
  (char_seq item, [> Error.t]) Core.Result.t Stream.t
(** Parse an input-channel into a stream of [char_seq item] results. *)

val in_channel_to_int_seq_item_stream :
  ?buffer_size:int ->
  ?filename:string ->
  ?tags:Tags.t ->
  in_channel ->
  (int_seq item, [> Error.t]) Core.Result.t Stream.t
(** Parse an input-channel into a stream of [int_seq item] results. *)


val in_channel_to_char_seq_item_stream_exn :
  ?buffer_size:int ->
  ?filename:string ->
  ?tags:Tags.t ->
  in_channel ->
  char_seq item Stream.t
(** Returns a stream of [char_seq item]s. Comments are
    discarded. [Stream.next] will raise [Error _] in case of any error. *)

val in_channel_to_int_seq_item_stream_exn :
  ?buffer_size:int ->
  ?filename:string ->
  ?tags:Tags.t ->
  in_channel ->
  int_seq item Stream.t
(** Returns a stream of [int_seq item]s. Comments are
    discarded.  [Stream.next] will raise [Error _] in case of any error. *)

val in_channel_to_char_seq_raw_item_stream :
  ?buffer_size:int ->
  ?filename:string ->
  ?tags:Tags.t ->
  in_channel ->
  (char_seq raw_item, [> Error.t]) Core.Result.t Stream.t
(** Parse an input-channel into a stream of [char_seq raw_item] results. *)

val in_channel_to_int_seq_raw_item_stream :
  ?buffer_size:int ->
  ?filename:string ->
  ?tags:Tags.t ->
  in_channel ->
  (int_seq raw_item, [> Error.t]) Core.Result.t Stream.t
(** Parse an input-channel into a stream of [int_seq raw_item] results. *)


val in_channel_to_char_seq_raw_item_stream_exn :
  ?buffer_size:int ->
  ?filename:string ->
  ?tags:Tags.t ->
  in_channel ->
  char_seq raw_item Stream.t
(** Returns a stream of [char_seq raw_item]s.  Comments are
    discarded. [Stream.next] will raise [Error _] in case of any error. *)

val in_channel_to_int_seq_raw_item_stream_exn :
  ?buffer_size:int ->
  ?filename:string ->
  ?tags:Tags.t ->
  in_channel ->
  int_seq raw_item Stream.t
(** Returns a stream of [int_seq raw_item]s. Comments are discarded.
    [Stream.next] will raise [Error _] in case of any error. *)

(** {2 [To_string] Functions }

    These functions convert [_ raw_item] value to strings that can be
    dumped to a file, i.e. they are full-lines, including end-of-line
    characters.
*)

val char_seq_raw_item_to_string: char_seq raw_item -> string
(** Convert a [raw_item] to a string (ignore comments). *)

val int_seq_raw_item_to_string: int_seq raw_item -> string
(** Convert a [raw_item] to a string (ignore comments). *)


(** {2 Transforms } *)

module Transform: sig
  (** Low-level transforms, c.f. {!module:Biocaml_transform}. *)

  (** {3 Parsers For [char_seq] Items} *)

  val string_to_char_seq_raw_item:
    ?filename:string ->
    ?tags:Tags.t ->
    unit ->
    (string, (char_seq raw_item, [> Error.t]) Core.Result.t) Biocaml_transform.t
  (** Parse a stream of strings as a char_seq FASTA file. *)

  val char_seq_raw_item_to_item:
    unit ->
    (char_seq raw_item,
     (char_seq item, [> `unnamed_char_seq of char_seq ]) Core.Result.t)
      Biocaml_transform.t
  (** Aggregate a stream of FASTA [char_seq raw_item]s into [char_seq
      item]s. Comments are discared. *)


  (** {3 Printers For [char_seq] Items} *)

  val char_seq_item_to_raw_item: ?tags:Tags.t -> unit ->
    (char_seq item, char_seq raw_item) Biocaml_transform.t
  (** Cut a stream of [char_seq item]s into a stream of [char_seq
      raw_item]s, where lines are cut at [items_per_line]
      characters (where [items_per_line] is defined with the
      [`max_items_per_line _] tag, if not specified the default is
      80). *)

  val char_seq_raw_item_to_string:
    ?tags:Tags.t ->
    unit ->
    (char_seq raw_item, string) Biocaml_transform.t
  (** Print [char_seq item]s. Comments will be ignored if
      neither of the tags [`sharp_comments] or
      [`semicolon_comments] is provided. *)


  (** {3 Parsers For [int_seq] Items} *)

  val string_to_int_seq_raw_item:
    ?filename:string ->
    ?tags:Tags.t ->
    unit ->
    (string, (int_seq raw_item, [> Error.t]) Core.Result.t) Biocaml_transform.t
  (** Parse a stream of strings as an int_seq FASTA file. *)

  val int_seq_raw_item_to_item:
    unit ->
    (int_seq raw_item,
     (int_seq item, [> `unnamed_int_seq of int_seq ]) Core.Result.t)
      Biocaml_transform.t
  (** Aggregate a stream of FASTA [int_seq raw_item]s into [int_seq
      item]s. Comments are discared. *)


  (** {3 Printers For [int_seq] Items} *)

  val int_seq_item_to_raw_item: ?tags:Tags.t -> unit ->
    (int_seq item, int_seq raw_item) Biocaml_transform.t
  (** Cut a stream of [int_seq item]s into a stream of [int_seq
      raw_item]s, the default line-cutting threshold is [27]
      (c.f. {!Tags.t}). *)

  val int_seq_raw_item_to_string:
    ?tags:Tags.t ->
    unit ->
    (int_seq raw_item, string) Biocaml_transform.t
  (** Print [int_seq item]s. Comments will be ignored if no
      [*_comments] tag is provided. *)

end

(** {2 Random Generation} *)
module Random: sig

  type specification = [
    | `non_sequence_probability of float
    | `tags of Tags.t
  ]
  (** The specification guiding the random generation of ['a raw_item]
      values is a list of [specification] values. {ul
        {li [`non_sequence_probability f] means that the output will {i
          not} be a [`partial_sequence _] item with probability [f].}
        {li [`tags t] specifies which [Tags.t] should be respected.}
      }
  *)

  val specification_of_string: string ->
    (specification list, [> `fasta of [> `parse_specification of exn]])
      Core.Std.Result.t
  (** Parse a [specification] from a [string]. Right now, the DSL is
      based on S-Expressions. *)

  val get_tags: [> specification] list -> Tags.t option
  (** Get the first [Tags.t] in the specification, if any. *)

  val unit_to_random_char_seq_raw_item: [> specification] list ->
    ((unit, char_seq raw_item) Biocaml_transform.t,
     [> `inconsistent_tags of [> `int_sequence ]]) Core.Result.t
  (** Create a transformation that generates random [char_seq
      raw_item] values according to the specification. *)


end


(** {2 S-expressions} *)

val sexp_of_char_seq : char_seq -> Sexplib.Sexp.t
val char_seq_of_sexp : Sexplib.Sexp.t -> char_seq
val sexp_of_int_seq : int_seq -> Sexplib.Sexp.t
val int_seq_of_sexp : Sexplib.Sexp.t -> int_seq
val sexp_of_item : ('a -> Sexplib.Sexp.t) -> 'a item -> Sexplib.Sexp.t
val item_of_sexp : (Sexplib.Sexp.t -> 'a) -> Sexplib.Sexp.t -> 'a item
val sexp_of_raw_item : ('a -> Sexplib.Sexp.t) -> 'a raw_item -> Sexplib.Sexp.t
val raw_item_of_sexp : (Sexplib.Sexp.t -> 'a) -> Sexplib.Sexp.t -> 'a raw_item
