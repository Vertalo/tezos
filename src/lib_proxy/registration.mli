(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

(** The module type of a proxy environment. Modules of this type should be
    prepared protocol-side and registered here to become available to the
    proxy facility. *)

module type Proxy_sig = sig
  val protocol_hash : Protocol_hash.t

  (** RPCs provided by the protocol *)
  val directory : Tezos_protocol_environment.rpc_context RPC_directory.t

  (** The protocol's /chains/<chain>/blocks/<block_id>/hash RPC *)
  val hash :
    #RPC_context.simple ->
    ?chain:Tezos_shell_services.Block_services.chain ->
    ?block:Tezos_shell_services.Block_services.block ->
    unit ->
    Block_hash.t tzresult Lwt.t

  (** How to build the context to execute RPCs on. Arguments are:

      - A printer (for logging)
      - An instance of [RPC_context.json], to perform RPCs
      - The chain for which the context is required
      - The block for which the context is required
    *)
  val init_env_rpc_context :
    Tezos_client_base.Client_context.printer ->
    RPC_context.json ->
    Tezos_shell_services.Block_services.chain ->
    Tezos_shell_services.Block_services.block ->
    Tezos_protocol_environment.rpc_context tzresult Lwt.t
end

type proxy_environment = (module Proxy_sig)

val register_proxy_context : proxy_environment -> unit

(** Returns a proxy environment for the given protocol (or the
    first one in the list of registered protocols
    if the [Protocol_hash.t] is [None], see the [Registration] module). *)
val get_registered_proxy :
  Protocol_hash.t option -> proxy_environment tzresult Lwt.t