(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

(** The rollup node maintains an inbox of incoming messages.

   The incoming messages for a rollup are published on the layer 1. To
   maintain the state of its inbox, a rollup node retrieves these
   messages each time the tezos blockchain is updated.

   The inbox state is persistent.

*)

open Protocol.Alpha_context

(** [process_head node_ctxt head operations] changes the state of the inbox to
    react to [head]. In particular, this process filters the provided
    [operations] of the [head] block. *)
val process_head : Node_context.rw -> Layer1.head -> Context.rw tzresult Lwt.t

(** [inbox_of_hash node_ctxt block_hash] returns the rollup inbox at the end of
    the given validation of [block_hash]. *)
val inbox_of_hash :
  _ Node_context.t ->
  Tezos_crypto.Block_hash.t ->
  Sc_rollup.Inbox.t tzresult Lwt.t

(** [history_of_hash node_ctxt block_hash] returns the rollup inbox history at
    the end of the given validation of [block_hash]. *)
val history_of_hash :
  _ Node_context.t ->
  Tezos_crypto.Block_hash.t ->
  Sc_rollup.Inbox.History.t tzresult Lwt.t

(** [inbox_of_head node_ctxt block_head] returns the rollup inbox at the end of
    the given validation of [block_head]. *)
val inbox_of_head :
  _ Node_context.t -> Layer1.head -> Sc_rollup.Inbox.t tzresult Lwt.t

(** [history_of_head node_ctxt block_head] returns the rollup inbox history at
    the end of the given validation of [block_head]. *)
val history_of_head :
  _ Node_context.t -> Layer1.head -> Sc_rollup.Inbox.History.t tzresult Lwt.t

(** [start ()] initializes the inbox to track the messages being published. *)
val start : unit -> unit Lwt.t

(** [add_messages inbox_level inbox history messages] adds
    [messages] to the [inbox] whose history is [history]. The new inbox level is
    given as [inbox_level]. Returns an updated [history] and [inbox], and a new
    [messages_history] and [messages_hash]. *)
val add_messages :
  Raw_level.t ->
  Sc_rollup.Inbox.t ->
  Store.Histories.value ->
  Sc_rollup.Inbox_message.t trace ->
  (Store.Level_tree_histories.value
  * Store.Level_tree_histories.key option
  * Store.Histories.value
  * Sc_rollup.Inbox.t)
  tzresult
  Lwt.t
