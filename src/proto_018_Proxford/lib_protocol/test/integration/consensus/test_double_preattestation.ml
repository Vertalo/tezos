(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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
    Component:  Protocol (double preattestation) in Full_construction & Application modes
    Invocation: dune exec src/proto_018_Proxford/lib_protocol/test/integration/consensus/main.exe \
                  -- --file test_double_preattestation.ml
    Subject:    These tests target different cases for double preattestation *)

open Protocol
open Alpha_context

module type MODE = sig
  val name : string

  val baking_mode : Block.baking_mode
end

module BakeWithMode (Mode : MODE) : sig
  val tests : unit Alcotest_lwt.test_case trace
end = struct
  let name = Mode.name

  let bake = Block.bake ~baking_mode:Mode.baking_mode

  let bake_n = Block.bake_n ~baking_mode:Mode.baking_mode

  (****************************************************************)
  (*                    Utility functions                         *)
  (****************************************************************)

  (** Helper function for illformed denunciations construction *)

  let pick_attesters ctxt =
    let module V = Plugin.RPC.Validators in
    Context.get_attesters ctxt >>=? function
    | a :: b :: _ ->
        return ((a.V.delegate, a.V.slots), (b.V.delegate, b.V.slots))
    | _ -> assert false

  let invalid_denunciation loc res =
    Assert.proto_error ~loc res (function
        | Validate_errors.Anonymous.Invalid_denunciation kind
          when kind = Validate_errors.Anonymous.Preattestation ->
            true
        | _ -> false)

  let malformed_double_preattestation_denunciation
      ?(include_attestation = false) ?(block_round = 0)
      ?(mk_evidence = fun ctxt p1 p2 -> Op.double_preattestation ctxt p1 p2)
      ~loc () =
    Context.init_n ~consensus_threshold:0 10 ()
    >>=? fun (genesis, _contracts) ->
    bake genesis >>=? fun b1 ->
    bake ~policy:(By_round 0) b1 >>=? fun b2_A ->
    Op.attestation b1 >>=? fun e ->
    let operations = if include_attestation then [e] else [] in
    bake ~policy:(By_round block_round) ~operations b1 >>=? fun b2_B ->
    Op.raw_preattestation b2_A >>=? fun op1 ->
    Op.raw_preattestation b2_B >>=? fun op2 ->
    let op = mk_evidence (B genesis) op1 op2 in
    bake b1 ~operations:[op] >>= fun res -> invalid_denunciation loc res

  let max_slashing_period () =
    Context.init1 ~consensus_threshold:0 () >>=? fun (genesis, _contract) ->
    Context.get_constants (B genesis)
    >>=? fun {parametric = {max_slashing_period; blocks_per_cycle; _}; _} ->
    return (max_slashing_period * Int32.to_int blocks_per_cycle)

  let already_denounced loc res =
    Assert.proto_error ~loc res (function
        | Validate_errors.Anonymous.Already_denounced {kind; _}
          when kind = Validate_errors.Anonymous.Preattestation ->
            true
        | _ -> false)

  let inconsistent_denunciation loc res =
    Assert.proto_error ~loc res (function
        | Validate_errors.Anonymous.Inconsistent_denunciation {kind; _}
          when kind = Validate_errors.Anonymous.Preattestation ->
            true
        | _ -> false)

  let outdated_denunciation loc res =
    Assert.proto_error ~loc res (function
        | Validate_errors.Anonymous.Outdated_denunciation {kind; _}
          when kind = Validate_errors.Anonymous.Preattestation ->
            true
        | _ -> false)

  let unexpected_failure loc res =
    (* no error is expected *)
    Assert.proto_error ~loc res (function _ -> false)

  let unexpected_success loc _ _ _ _ _ =
    Alcotest.fail (loc ^ ": Test should not succeed")

  let expected_success _loc baker pred bbad d1 d2 =
    (* same preattesters in case denunciation succeeds*)
    Assert.equal_pkh ~loc:__LOC__ d1 d2 >>=? fun () ->
    Context.get_constants (B pred) >>=? fun constants ->
    let p =
      constants.parametric
        .percentage_of_frozen_deposits_slashed_per_double_attestation
    in
    (* let's bake the block on top of pred without denunciating d1 *)
    bake ~policy:(By_account baker) pred >>=? fun bgood ->
    (* Checking what the attester lost *)
    Context.Delegate.current_frozen_deposits (B pred) d1
    >>=? fun frozen_deposit ->
    Context.Delegate.full_balance (B bgood) d1 >>=? fun bal_good ->
    Context.Delegate.full_balance (B bbad) d1 >>=? fun bal_bad ->
    (* the diff of the two balances in normal and in denunciation cases *)
    let diff_end_bal = Test_tez.(bal_good -! bal_bad) in
    (* amount lost due to denunciation *)
    let lost_deposit = Test_tez.(frozen_deposit *! Int64.of_int p /! 100L) in
    (* some of the lost deposits (depending on staking constants) will be earned by the baker *)
    let divider =
      Int64.add
        2L
        (Int64.of_int
           constants.parametric.adaptive_issuance
             .global_limit_of_staking_over_baking)
    in
    let denun_reward = Test_tez.(lost_deposit /! divider) in
    (* if the baker is the attester, he'll only loose half of the deposits *)
    let expected_attester_loss =
      if Signature.Public_key_hash.equal baker d1 then
        Test_tez.(lost_deposit -! denun_reward)
      else lost_deposit
    in
    Assert.equal_tez ~loc:__LOC__ expected_attester_loss diff_end_bal
    >>=? fun () ->
    (* Checking what the baker earned (or lost) *)
    Context.Delegate.full_balance (B bgood) baker >>=? fun bal_good ->
    Context.Delegate.full_balance (B bbad) baker >>=? fun bal_bad ->
    (* if baker = attester, the baker's balance in the good case is better,
       because half of his deposits are burnt in the bad (double-preattestation)
       situation. In case baker <> attester, bal_bad of the baker gets half of
       burnt deposit of d1, so it's higher
    *)
    let high, low =
      if Signature.Public_key_hash.equal baker d1 then (bal_good, bal_bad)
      else (bal_bad, bal_good)
    in
    let diff_baker = Test_tez.(high -! low) in
    (* the baker has either earnt or lost (in case baker = d1) half of burnt
       attestation deposits *)
    Assert.equal_tez ~loc:__LOC__ denun_reward diff_baker >>=? fun () ->
    return_unit

  let order_preattestations ~correct_order op1 op2 =
    let oph1 = Operation.hash op1 in
    let oph2 = Operation.hash op2 in
    let c = Operation_hash.compare oph1 oph2 in
    if correct_order then if c < 0 then (op1, op2) else (op2, op1)
    else if c < 0 then (op2, op1)
    else (op1, op2)

  (** Helper function for denunciations inclusion *)
  let generic_double_preattestation_denunciation ~nb_blocks_before_double
      ~nb_blocks_before_denunciation
      ?(test_expected_ok = fun _loc _baker _pred _bbad _d1 _d2 -> return_unit)
      ?(test_expected_ko = fun _loc _res -> return_unit)
      ?(pick_attesters =
        fun ctxt -> pick_attesters ctxt >>=? fun (a, _b) -> return (a, a)) ~loc
      () =
    Context.init_n ~consensus_threshold:0 10 () >>=? fun (genesis, contracts) ->
    let addr =
      match List.hd contracts with None -> assert false | Some e -> e
    in
    (* bake `nb_blocks_before_double blocks` before double preattesting *)
    bake_n nb_blocks_before_double genesis >>=? fun blk ->
    (* producing two differents blocks and two preattestations op1 and op2 *)
    Op.transaction (B genesis) addr addr Tez.one_mutez >>=? fun trans ->
    bake ~policy:(By_round 0) blk >>=? fun head_A ->
    bake ~policy:(By_round 0) blk ~operations:[trans] >>=? fun head_B ->
    pick_attesters (B head_A) >>=? fun ((d1, _slots1), (d2, _slots2)) ->
    (* default: d1 = d2 *)
    Op.raw_preattestation ~delegate:d1 head_A >>=? fun op1 ->
    Op.raw_preattestation ~delegate:d2 head_B >>=? fun op2 ->
    let op1, op2 = order_preattestations ~correct_order:true op1 op2 in
    (* bake `nb_blocks_before_denunciation` before double preattestation denunciation *)
    bake_n nb_blocks_before_denunciation blk >>=? fun blk ->
    let op : Operation.packed = Op.double_preattestation (B blk) op1 op2 in
    Context.get_baker (B blk) ~round:Round.zero >>=? fun baker ->
    bake ~policy:(By_account baker) blk ~operations:[op] >>= function
    | Ok new_head ->
        test_expected_ok loc baker blk new_head d1 d2 >>=? fun () ->
        let op : Operation.packed =
          Op.double_preattestation (B new_head) op2 op1
        in
        bake new_head ~operations:[op] >>= invalid_denunciation loc
        >>=? fun () ->
        let op : Operation.packed =
          Op.double_preattestation (B new_head) op1 op2
        in
        bake new_head ~operations:[op] >>= already_denounced loc
    | Error _ as res -> test_expected_ko loc res

  (****************************************************************)
  (*                      Tests                                   *)
  (****************************************************************)

  (** Preattesting two blocks that are structurally equal is not punished *)
  let malformed_double_preattestation_denunciation_same_payload_hash_1 () =
    malformed_double_preattestation_denunciation ~loc:__LOC__ ()

  (** Preattesting two blocks that are structurally equal up to the attestations
    they include is not punished *)
  let malformed_double_preattestation_denunciation_same_payload_hash_2 () =
    malformed_double_preattestation_denunciation
    (* including an attestation in one of the blocks doesn't change its
       payload hash *)
      ~include_attestation:true
      ~loc:__LOC__
      ()

  (** Denunciation evidence cannot have the same operations *)
  let malformed_double_preattestation_denunciation_same_preattestation () =
    malformed_double_preattestation_denunciation
    (* exactly the same preattestation operation => illformed *)
      ~mk_evidence:(fun ctxt p1 _p2 -> Op.double_preattestation ctxt p1 p1)
      ~loc:__LOC__
      ()

  (** Preattesting two blocks with different rounds is not punished *)
  let malformed_double_preattestation_denunciation_different_rounds () =
    malformed_double_preattestation_denunciation ~loc:__LOC__ ~block_round:1 ()

  (** Preattesting two blocks by two different validators is not punished *)
  let malformed_double_preattestation_denunciation_different_validators () =
    generic_double_preattestation_denunciation
      ~nb_blocks_before_double:0
      ~nb_blocks_before_denunciation:2
      ~test_expected_ok:unexpected_success
      ~test_expected_ko:inconsistent_denunciation
      ~pick_attesters (* pick different attesters *)
      ~loc:__LOC__
      ()

  (** Attempt a denunciation of a double-pre in the first block after genesis *)
  let double_preattestation_just_after_upgrade () =
    generic_double_preattestation_denunciation
      ~nb_blocks_before_double:0
      ~nb_blocks_before_denunciation:1
      ~test_expected_ok:expected_success
      ~test_expected_ko:unexpected_failure
      ~loc:__LOC__
      ()

  (** Denunciation of double-pre at level L is injected at level L' = max_slashing_period.
    The denunciation is outdated. *)
  let double_preattestation_denunciation_during_slashing_period () =
    max_slashing_period () >>=? fun max_slashing_period ->
    generic_double_preattestation_denunciation
      ~nb_blocks_before_double:0
      ~nb_blocks_before_denunciation:(max_slashing_period / 2)
      ~test_expected_ok:expected_success
      ~test_expected_ko:unexpected_failure
      ~loc:__LOC__
      ()

  (** Denunciation of double-pre at level L is injected 1 block after unfreeze
      delay. Too late: denunciation is outdated. *)
  let double_preattestation_denunciation_after_slashing_period () =
    max_slashing_period () >>=? fun max_slashing_period ->
    generic_double_preattestation_denunciation
      ~nb_blocks_before_double:0
      ~nb_blocks_before_denunciation:(max_slashing_period + 1)
      ~test_expected_ok:unexpected_success
      ~test_expected_ko:outdated_denunciation
      ~loc:__LOC__
      ()

  let double_preattestation ctxt ?(correct_order = true) op1 op2 =
    let e1, e2 = order_preattestations ~correct_order op1 op2 in
    Op.double_preattestation ctxt e1 e2

  let block_fork b =
    Context.get_first_different_bakers (B b) >>=? fun (baker_1, baker_2) ->
    Block.bake ~policy:(By_account baker_1) b >>=? fun blk_a ->
    Block.bake ~policy:(By_account baker_2) b >|=? fun blk_b -> (blk_a, blk_b)

  (** Injecting a valid double preattestation multiple time raises an error. *)
  let test_two_double_preattestation_evidences_leads_to_duplicate_denunciation
      () =
    Context.init2 ~consensus_threshold:0 () >>=? fun (genesis, _contracts) ->
    block_fork genesis >>=? fun (blk_1, blk_2) ->
    Block.bake blk_1 >>=? fun blk_a ->
    Block.bake blk_2 >>=? fun blk_b ->
    Context.get_attester (B blk_a) >>=? fun (delegate, _) ->
    Op.raw_preattestation blk_a >>=? fun preattestation_a ->
    Op.raw_preattestation blk_b >>=? fun preattestation_b ->
    let operation =
      double_preattestation (B genesis) preattestation_a preattestation_b
    in
    let operation2 =
      double_preattestation (B genesis) preattestation_b preattestation_a
    in
    Context.get_bakers (B blk_a) >>=? fun bakers ->
    let baker = Context.get_first_different_baker delegate bakers in
    Context.Delegate.full_balance (B blk_a) baker
    >>=? fun (_full_balance : Tez.t) ->
    Block.bake
      ~policy:(By_account baker)
      ~operations:[operation; operation2]
      blk_a
    >>= fun e ->
    Assert.proto_error ~loc:__LOC__ e (function
        | Validate_errors.Anonymous.Conflicting_denunciation {kind; _}
          when kind = Validate_errors.Anonymous.Preattestation ->
            true
        | _ -> false)
    >>=? fun () ->
    Block.bake ~policy:(By_account baker) ~operation blk_a
    >>=? fun blk_with_evidence1 ->
    Block.bake ~policy:(By_account baker) ~operation blk_with_evidence1
    >>= fun e -> already_denounced __LOC__ e

  let my_tztest title test =
    Tztest.tztest (Format.sprintf "%s: %s" name title) test

  let tests =
    [
      (* illformed denunciations *)
      my_tztest
        "ko: malformed_double_preattestation_denunciation_same_payload_hash_1"
        `Quick
        malformed_double_preattestation_denunciation_same_payload_hash_1;
      my_tztest
        "ko: malformed_double_preattestation_denunciation_same_payload_hash_2"
        `Quick
        malformed_double_preattestation_denunciation_same_payload_hash_2;
      my_tztest
        "ko: malformed_double_preattestation_denunciation_different_rounds"
        `Quick
        malformed_double_preattestation_denunciation_different_rounds;
      my_tztest
        "ko: malformed_double_preattestation_denunciation_same_preattestation"
        `Quick
        malformed_double_preattestation_denunciation_same_preattestation;
      my_tztest
        "ko: malformed_double_preattestation_denunciation_different_validators"
        `Quick
        malformed_double_preattestation_denunciation_different_validators;
      my_tztest
        "double_preattestation_just_after_upgrade"
        `Quick
        double_preattestation_just_after_upgrade;
      (* tests for unfreeze *)
      my_tztest
        "double_preattestation_denunciation_during_slashing_period"
        `Quick
        double_preattestation_denunciation_during_slashing_period;
      my_tztest
        "double_preattestation_denunciation_after_slashing_period"
        `Quick
        double_preattestation_denunciation_after_slashing_period;
      my_tztest
        "valid double preattestation injected multiple times"
        `Quick
        test_two_double_preattestation_evidences_leads_to_duplicate_denunciation;
    ]
end

let tests =
  let module AppMode = BakeWithMode (struct
    let name = "AppMode"

    let baking_mode = Block.Application
  end) in
  let module ConstrMode = BakeWithMode (struct
    let name = "ConstrMode"

    let baking_mode = Block.Baking
  end) in
  AppMode.tests @ ConstrMode.tests

let () =
  Alcotest_lwt.run ~__FILE__ Protocol.name [("double preattestation", tests)]
  |> Lwt_main.run
