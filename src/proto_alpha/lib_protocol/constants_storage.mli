(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020-2021 Nomadic Labs <contact@nomadic-labs.com>           *)
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

val preserved_cycles : Raw_context.context -> int

val blocks_per_cycle : Raw_context.context -> int32

val blocks_per_commitment : Raw_context.context -> int32

val blocks_per_roll_snapshot : Raw_context.context -> int32

val blocks_per_voting_period : Raw_context.context -> int32

val time_between_blocks : Raw_context.context -> Period_repr.t list

val endorsers_per_block : Raw_context.context -> int

val initial_endorsers : Raw_context.context -> int

val delay_per_missing_endorsement : Raw_context.context -> Period_repr.t

val hard_gas_limit_per_operation :
  Raw_context.context -> Gas_limit_repr.Arith.integral

val hard_gas_limit_per_block :
  Raw_context.context -> Gas_limit_repr.Arith.integral

val cost_per_byte : Raw_context.context -> Tez_repr.t

val hard_storage_limit_per_operation : Raw_context.context -> Z.t

val proof_of_work_threshold : Raw_context.context -> int64

val tokens_per_roll : Raw_context.context -> Tez_repr.t

val michelson_maximum_type_size : Raw_context.context -> int

val seed_nonce_revelation_tip : Raw_context.context -> Tez_repr.t

val origination_size : Raw_context.context -> int

val block_security_deposit : Raw_context.context -> Tez_repr.t

val endorsement_security_deposit : Raw_context.context -> Tez_repr.t

val baking_reward_per_endorsement : Raw_context.context -> Tez_repr.t list

val endorsement_reward : Raw_context.context -> Tez_repr.t list

val quorum_min : Raw_context.context -> int32

val quorum_max : Raw_context.context -> int32

val min_proposal_quorum : Raw_context.context -> int32

val parametric : Raw_context.context -> Constants_repr.parametric
