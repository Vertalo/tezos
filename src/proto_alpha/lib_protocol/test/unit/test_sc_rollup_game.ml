(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Trili Tech, <contact@trili.tech>                       *)
(* Copyright (c) 2022 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** Testing
    -------
    Component:  Protocol Sc_rollup_refutation_storage
    Invocation: dune exec src/proto_alpha/lib_protocol/test/unit/main.exe \
      -- test "^\[Unit\] sc rollup game$"
    Subject:    Tests for the SCORU refutation game
*)

open Protocol
open Lwt_result_syntax
module Commitment_repr = Sc_rollup_commitment_repr
module T = Test_sc_rollup_storage
module R = Sc_rollup_refutation_storage
module G = Sc_rollup_game_repr
module Tick = Sc_rollup_tick_repr

let check_reason ~loc (outcome : Sc_rollup_game_repr.outcome option) s =
  match outcome with
  | None -> assert false
  | Some o -> (
      match o.reason with
      | Conflict_resolved -> assert false
      | Timeout -> assert false
      | Invalid_move r ->
          Assert.equal
            ~loc
            String.equal
            "Compare invalid_move reasons"
            Format.pp_print_string
            r
            s)

let tick_of_int_exn n =
  match Tick.of_int n with None -> assert false | Some t -> t

let context_hash_of_string s = Context_hash.hash_string [s]

let hash_string s =
  Sc_rollup_repr.State_hash.context_hash_to_state_hash
  @@ context_hash_of_string s

let hash_int n = hash_string (Format.sprintf "%d" n)

let mk_dissection_chunk (state_hash, tick) = G.{state_hash; tick}

let init_dissection ~size ?init_tick start_hash =
  let default_init_tick i =
    let hash =
      if i = size - 1 then None
      else Some (if i = 0 then start_hash else hash_int i)
    in
    mk_dissection_chunk (hash, tick_of_int_exn i)
  in
  let init_tick =
    Option.fold
      ~none:default_init_tick
      ~some:(fun init_tick -> init_tick size)
      init_tick
  in
  Stdlib.List.init size init_tick

let init_refutation ~size ?init_tick start_hash =
  G.
    {
      choice = Sc_rollup_tick_repr.initial;
      step = Dissection (init_dissection ~size ?init_tick start_hash);
    }

let two_stakers_in_conflict () =
  let* ctxt, rollup, genesis_hash, refuter, defender =
    T.originate_rollup_and_deposit_with_two_stakers ()
  in
  let hash1 = hash_string "foo" in
  let hash2 = hash_string "bar" in
  let hash3 = hash_string "xyz" in
  let parent_commit =
    Commitment_repr.
      {
        predecessor = genesis_hash;
        inbox_level = T.valid_inbox_level ctxt 1l;
        number_of_ticks = T.number_of_ticks_exn 152231l;
        compressed_state = hash1;
      }
  in
  let* parent, _, ctxt =
    T.lift
    @@ Sc_rollup_stake_storage.Internal_for_tests.refine_stake
         ctxt
         rollup
         defender
         parent_commit
  in
  let child1 =
    Commitment_repr.
      {
        predecessor = parent;
        inbox_level = T.valid_inbox_level ctxt 2l;
        number_of_ticks = T.number_of_ticks_exn 10000l;
        compressed_state = hash2;
      }
  in
  let child2 =
    Commitment_repr.
      {
        predecessor = parent;
        inbox_level = T.valid_inbox_level ctxt 2l;
        number_of_ticks = T.number_of_ticks_exn 10000l;
        compressed_state = hash3;
      }
  in
  let* _, _, ctxt, _ =
    T.lift
    @@ Sc_rollup_stake_storage.publish_commitment ctxt rollup defender child1
  in
  let* _, _, ctxt, _ =
    T.lift
    @@ Sc_rollup_stake_storage.publish_commitment ctxt rollup refuter child2
  in
  return (ctxt, rollup, refuter, defender)

(** A dissection is 'poorly distributed' if its tick counts are not
    very evenly spread through the total tick-duration. Formally, the
    maximum tick-distance between two consecutive states in a dissection
    may not be more than half of the total tick-duration. *)
let test_poorly_distributed_dissection () =
  let* ctxt, rollup, refuter, defender = two_stakers_in_conflict () in
  let start_hash = hash_string "foo" in
  let init_tick size i =
    mk_dissection_chunk
    @@
    if i = size - 1 then (None, tick_of_int_exn 10000)
    else (Some (if i = 0 then start_hash else hash_int i), tick_of_int_exn i)
  in
  let* ctxt =
    T.lift @@ R.start_game ctxt rollup ~player:refuter ~opponent:defender
  in
  let size =
    Constants_storage.sc_rollup_number_of_sections_in_dissection ctxt
  in
  let move = init_refutation ~size ~init_tick start_hash in
  let* outcome, _ctxt =
    T.lift @@ R.game_move ctxt rollup ~player:refuter ~opponent:defender move
  in
  let expected_reason =
    "Maximum tick increment in dissection must be less than half total \
     dissection length"
  in
  check_reason ~loc:__LOC__ outcome expected_reason

let test_single_valid_game_move () =
  let* ctxt, rollup, refuter, defender = two_stakers_in_conflict () in
  let start_hash = hash_string "foo" in
  let size =
    Constants_storage.sc_rollup_number_of_sections_in_dissection ctxt
  in
  let tick_per_state = 10_000 / size in
  let dissection =
    Stdlib.List.init size (fun i ->
        mk_dissection_chunk
        @@
        if i = 0 then (Some start_hash, tick_of_int_exn 0)
        else if i = size - 1 then (None, tick_of_int_exn 10000)
        else (Some (hash_int i), tick_of_int_exn (i * tick_per_state)))
  in
  let* ctxt =
    T.lift @@ R.start_game ctxt rollup ~player:refuter ~opponent:defender
  in
  let move =
    Sc_rollup_game_repr.
      {choice = Sc_rollup_tick_repr.initial; step = Dissection dissection}
  in
  let* outcome, _ctxt =
    T.lift @@ R.game_move ctxt rollup ~player:refuter ~opponent:defender move
  in
  Assert.is_none ~loc:__LOC__ ~pp:Sc_rollup_game_repr.pp_outcome outcome

(* In order to test that a staker cannot play two refutation games at once (see
   {!Sc_rollup_refutation_storage}), we first create a situation where a
   defender is up against a refuter. This test should pass.
   Then we initiate the same configuration, but with another refuter playing
   against the same defender. This test should fail.
   Note that the first test where everything goes right is not mandatory: we
   will check that the error raised in the second test is exactly
   [Sc_rollup_staker_in_game], so this should be enough to verify the property.
   However, having a successful test can help us understand what went wrong if
   the tests don't pass after some code modifications.

   First, the function below creates a context with three stakers: one
   defender and two refuters. But the second refuter will play only if the
   [refuter2_plays] boolean parameter below is [true].
   Then, the function is instantiated twice (with [refuter2_plays] set to
   [false] and then to [true]) in order to create the tests described above. *)
let staker_injectivity_gen ~refuter2_plays =
  (* Create the defender and the two refuters. *)
  let+ ctxt, rollup, genesis_hash, refuter1, refuter2, defender =
    T.originate_rollup_and_deposit_with_three_stakers ()
  in
  let res =
    (* Create and publish four commits:
       * [commit1]: the base commit published by [defender] and that everybody
         agrees on;
       and then three commits whose [commit1] is the predecessor and that will
       be challenged in the refutation game:
       * [commit2]: published by [defender];
       * [commit3]: published by [refuter1];
       * [commit4]: published by [refuter2]. *)
    let hash1 = hash_string "foo" in
    let hash2 = hash_string "bar" in
    let hash3 = hash_string "xyz" in
    let hash4 = hash_string "abc" in
    let size =
      Constants_storage.sc_rollup_number_of_sections_in_dissection ctxt
    in
    let refutation = init_refutation ~size hash1 in
    let commit1 =
      Commitment_repr.
        {
          predecessor = genesis_hash;
          inbox_level = T.valid_inbox_level ctxt 1l;
          number_of_ticks = T.number_of_ticks_exn 152231l;
          compressed_state = hash1;
        }
    in
    let* c1_hash, _, ctxt =
      T.lift
      @@ Sc_rollup_stake_storage.Internal_for_tests.refine_stake
           ctxt
           rollup
           defender
           commit1
    in
    let challenging_commit compressed_state =
      Commitment_repr.
        {
          predecessor = c1_hash;
          inbox_level = T.valid_inbox_level ctxt 2l;
          number_of_ticks = T.number_of_ticks_exn 10000l;
          compressed_state;
        }
    in
    let commit2 = challenging_commit hash2 in
    let commit3 = challenging_commit hash3 in
    let commit4 = challenging_commit hash4 in
    (* Publish the commits. *)
    let publish_commitment ctxt staker commit =
      let+ _, _, ctxt, _ =
        T.lift
        @@ Sc_rollup_stake_storage.publish_commitment ctxt rollup staker commit
      in
      ctxt
    in
    let* ctxt = publish_commitment ctxt defender commit2 in
    let* ctxt = publish_commitment ctxt refuter1 commit3 in
    let* ctxt = publish_commitment ctxt refuter2 commit4 in
    (* Start the games. [refuter2] plays only if [refuter2_plays] is [true]. *)
    let game_move ctxt ~player ~opponent =
      let* ctxt = T.lift @@ R.start_game ctxt rollup ~player ~opponent in
      let+ _, ctxt =
        T.lift @@ R.game_move ctxt rollup ~player ~opponent refutation
      in
      ctxt
    in
    let* ctxt = game_move ctxt ~player:refuter1 ~opponent:defender in
    let+ _ctxt =
      if refuter2_plays then game_move ctxt ~player:refuter2 ~opponent:defender
      else return ctxt
    in
    ()
  in
  (refuter1, refuter2, defender, res)

(** Test that a staker can be part of at most one refutation game. *)
let test_staker_injectivity () =
  (* Test that it's OK to have three stakers where only two of them are
     playing. *)
  let* _ = staker_injectivity_gen ~refuter2_plays:false in
  (* Test that an error is triggered if a defender plays against two refuters at
     once. *)
  let* _, _, defender, res = staker_injectivity_gen ~refuter2_plays:true in
  let open Lwt_syntax in
  let* res = res in
  Assert.proto_error
    ~loc:__LOC__
    res
    (( = ) (Sc_rollup_errors.Sc_rollup_staker_in_game (`Defender defender)))

let tests =
  [
    Tztest.tztest
      "A badly distributed dissection is an invalid move."
      `Quick
      test_poorly_distributed_dissection;
    Tztest.tztest
      "A single game move with a valid dissection"
      `Quick
      test_single_valid_game_move;
    Tztest.tztest
      "Staker can be in at most one game (injectivity)."
      `Quick
      test_staker_injectivity;
  ]