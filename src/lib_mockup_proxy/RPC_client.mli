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

type rpc_error =
  | Rpc_generic_error of string option
  (* This case is caught by the proxy mode: when it is raised, the proxy
     delegates to the node *)
  | Rpc_not_found of string option
  | Rpc_unauthorized of string option
  | Rpc_unexpected_type_of_failure
  | Rpc_cannot_parse_path
  | Rpc_cannot_parse_query
  | Rpc_cannot_parse_body
  | Rpc_streams_not_handled

type error += Local_RPC_error of rpc_error

(** Exception used by the proxy mode when creation of the input
    environment (of the RPC handler) fails. This exception is used
    to temporarily escape from monad, because at the point
    of throwing, the code is NOT in tzresult Lwt.t (because it's dealing
    with resto APIs: it's in an Lwt.t-only monad).
    Then this exception is injected back in the
    tzresult Lwt.t monad at the point where it is caught (with Lwt.catch). *)
exception Rpc_dir_creation_failure of tztrace

(** The class [local_ctxt directory] creates
    an RPC context that executes RPCs locally. *)
class local_ctxt : unit RPC_directory.t -> RPC_context.json
