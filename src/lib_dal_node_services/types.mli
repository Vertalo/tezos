(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

module Cryptobox = Tezos_crypto_dal.Cryptobox

(** A Tezos level. *)
type level = int32

(** An index of a DAL slot header. *)
type slot_index = int

(** An ID associated to a slot or to its commitment. *)
type slot_id = {slot_level : level; slot_index : slot_index}

(** Definition of a topic used for gossipsub. *)
type topic = {slot_index : int; pkh : Signature.Public_key_hash.t}

(** Encoding of a topic. *)
val topic_encoding : topic Data_encoding.t

(* TODO: https://gitlab.com/tezos/tezos/-/issues/4562
   Use a bitset instead, when available in the standard library. *)

(** A set of slots, represented by a list of booleans (false for not in the
      set). It is used for instance to record which slots are deemed available
      by an attester. The level at which the slots have been published is also
      given. *)
type slot_set = {slots : bool list; published_level : int32}

(** The set of attestable slots of an attester (which may not necessarily be
      in the committee for a given level). *)
type attestable_slots = Attestable_slots of slot_set | Not_in_committee

(** An index of a DAL shard *)
type shard_index = int

(** The status of a header a DAL node is aware of: *)
type header_status =
  [ `Waiting_attestation
    (** The slot header was included and applied in a finalized L1 block
          but remains to be attested. *)
  | `Attested  (** The slot header was included in an L1 block and attested. *)
  | `Unattested
    (** The slot header was included in an L1 block but not timely attested. *)
  | `Not_selected
    (** The slot header was included in an L1 block but was not selected as
          the slot header for that slot index. *)
  | `Unseen_or_not_finalized
    (** The slot header was not seen in a *final* L1 block. For instance, this
          could happen if the RPC `PATCH /commitments/<commitment>` was called
          but the corresponding slot header was never included into a block; or
          the slot header was included in a non-final (ie not agreed upon)
          block. This means that the publish operation was not sent (yet) to L1,
          or sent but not included (yet) in a block, or included in a not (yet)
          final block. *)
  ]

(** Profiles that operate on shards/slots. *)
type operator_profile =
  | Attester of Tezos_crypto.Signature.public_key_hash
      (** [Attester pkh] downloads all shards assigned to [pkh].
            Used by bakers to attest availability of their assigned shards. *)
  | Producer of {slot_index : int}
      (** [Producer {slot_index}] produces/publishes slot for slot index [slot_index]. *)

(** List of operator profiles. It may contain dupicates as it represents profiles
      provided by the user in unprocessed form. *)
type operator_profiles = operator_profile list

(** DAL node can track one or many profiles that correspond to various modes
      that the DAL node would operate in. *)
type profiles =
  | Bootstrap
      (** The bootstrap profile facilitates peer discovery in the DAL network.
            Note that bootstrap nodes are incompatible with attester/producer profiles
            as bootstrap nodes are expected to connect to all the meshes with degree 0. *)
  | Operator of operator_profiles

(** Information associated to a slot header in the RPC services of the DAL
      node. *)
type slot_header = {
  slot_id : slot_id;
  commitment : Cryptobox.Commitment.t;
  status : header_status;
}

(** The [with_proof] flag is associated to shards computation. It indicates
      whether we also compute shards' proofs or not. *)
type with_proof = {with_proof : bool}

val slot_id_query : (level option * shard_index option) Resto.Query.t

val opt_header_status_query : header_status option Resto.Query.t

val slot_encoding : Cryptobox.slot Data_encoding.t

val slot_header_encoding : slot_header Data_encoding.t

val slot_id_encoding : slot_id Data_encoding.t

val header_status_encoding : header_status Data_encoding.t

val profiles_encoding : profiles Data_encoding.t

val with_proof_encoding : with_proof Data_encoding.t

val operator_profile_encoding : operator_profile Data_encoding.t

val attestable_slots_encoding : attestable_slots Data_encoding.t

module Store : sig
  (** [stored_data] is the kind of data being encoded/decoded. This
    datatype is used to get better events UX. *)
  type kind = Commitment | Header_status | Slot_id | Slot | Profile

  val encoding : kind Data_encoding.t

  val to_string : kind -> string
end
