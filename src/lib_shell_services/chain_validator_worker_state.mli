(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020 Nomadic Labs. <contact@nomadic-labs.com>               *)
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

module Request : sig
  type view = Hash of Tezos_crypto.Block_hash.t | PeerId of P2p_peer.Id.t

  val encoding : view Data_encoding.encoding

  val pp : Format.formatter -> view -> unit
end

type synchronisation_status =
  | Synchronised of {is_chain_stuck : bool}
  | Not_synchronised

val sync_status_encoding : synchronisation_status Data_encoding.t

val sync_status_pp : Format.formatter -> synchronisation_status -> unit

type update = Ignored_head | Branch_switch | Head_increment

val update_encoding : update Data_encoding.t

module Distributed_db_state : sig
  type table_scheduler = {table_length : int; scheduler_length : int}

  type view = {
    p2p_readers_length : int;
    active_chains_length : int;
    operation_db : table_scheduler;
    operations_db : table_scheduler;
    block_header_db : table_scheduler;
    active_connections_length : int;
    active_peers_length : int;
  }

  val encoding : view Data_encoding.encoding
end
