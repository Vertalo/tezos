(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020 Metastate AG <hello@metastate.dev>                     *)
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

type staker = Staker_repr.staker =
  | Single of Contract_repr.t * Signature.public_key_hash
  | Shared of Signature.public_key_hash

(** Places where tokens can be found in the ledger's state. *)
type 'token balance =
  | Contract : Contract_repr.t -> Tez_repr.t balance
  | Block_fees : Tez_repr.t balance
  | Deposits : staker -> Tez_repr.t balance
  | Unstaked_deposits : staker * Cycle_repr.t -> Tez_repr.t balance
  | Nonce_revelation_rewards : Tez_repr.t balance
  | Attesting_rewards : Tez_repr.t balance
  | Baking_rewards : Tez_repr.t balance
  | Baking_bonuses : Tez_repr.t balance
  | Storage_fees : Tez_repr.t balance
  | Double_signing_punishments : Tez_repr.t balance
  | Lost_attesting_rewards :
      Signature.Public_key_hash.t * bool * bool
      -> Tez_repr.t balance
  | Liquidity_baking_subsidies : Tez_repr.t balance
  | Burned : Tez_repr.t balance
  | Commitments : Blinded_public_key_hash.t -> Tez_repr.t balance
  | Bootstrap : Tez_repr.t balance
  | Invoice : Tez_repr.t balance
  | Initial_commitments : Tez_repr.t balance
  | Minted : Tez_repr.t balance
  | Frozen_bonds : Contract_repr.t * Bond_id_repr.t -> Tez_repr.t balance
  | Sc_rollup_refutation_punishments : Tez_repr.t balance
  | Sc_rollup_refutation_rewards : Tez_repr.t balance

(** Compares two balances. *)
val compare_balance : Tez_repr.t balance -> Tez_repr.t balance -> int

(** A credit or debit of tez to a balance. *)
type balance_update = Debited of Tez_repr.t | Credited of Tez_repr.t

(** An origin of a balance update *)
type update_origin =
  | Block_application  (** Update from a block application *)
  | Protocol_migration  (** Update from a protocol migration *)
  | Subsidy  (** Update from an inflationary subsidy  *)
  | Simulation  (** Simulation of an operation **)

(** Compares two origins. *)
val compare_update_origin : update_origin -> update_origin -> int

(** An item in a list of balance updates. 
    An item of the form [(Rewards (b,c), Credited am, ...)] indicates that the
    balance of frozen rewards has been increased by [am] for baker [b] and cycle
    [c]. *)
type balance_update_item = private
  | Balance_update_item :
      Tez_repr.t balance * balance_update * update_origin
      -> balance_update_item

(** Smart constructor for [balance_update_item]. *)
val item :
  Tez_repr.t balance -> balance_update -> update_origin -> balance_update_item

(** A list of balance updates. Duplicates may happen. *)
type balance_updates = balance_update_item list

(** The property [Json.destruct (Json.construct balance_updates) = balance_updates]
    does not always hold for [balance_updates_encoding] when [balance_updates]
    contains entries of the form [(_, _ Tez_repr.zero, _)]. This is because the
    [balance_update] [(_ Tez_repr.zero)] always decodes into [(Credited Tez_repr.zero)]. *)
val balance_updates_encoding : balance_updates Data_encoding.t

(** Balance updates encoding that uses legacy attestation name : `endorsing
    right` and `lost endorsing right` when encoding to JSON

    https://gitlab.com/tezos/tezos/-/issues/5529

    This encoding is temporary and should be removed when the endorsements kinds
    in JSON will not be accepted any more by the protocol.
*)
val balance_updates_encoding_with_legacy_attestation_name :
  balance_updates Data_encoding.t

(** Group updates by (balance x origin), and remove zero-valued balances. *)
val group_balance_updates : balance_updates -> balance_updates tzresult
