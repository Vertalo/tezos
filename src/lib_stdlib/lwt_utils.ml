(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2018-2021 Nomadic Labs, <contact@nomadic-labs.com>          *)
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

open Lwt.Syntax

let never_ending () = fst (Lwt.wait ())

(* A worker launcher, takes a cancel callback to call upon *)
let worker name ~on_event ~run ~cancel =
  let (stop, stopper) = Lwt.wait () in
  let fail e =
    Lwt.finalize
      (fun () ->
        on_event
          name
          (`Failed (Printf.sprintf "Exception: %s" (Printexc.to_string e))))
      cancel
  in
  let* () = on_event name `Started in
  let p = Lwt.catch run fail in
  Lwt.on_termination p (Lwt.wakeup stopper) ;
  let* () = stop in
  Lwt.catch (fun () -> on_event name `Ended) (fun _ -> Lwt.return_unit)

let worker name ~on_event ~run ~cancel =
  Lwt.no_cancel (worker name ~on_event ~run ~cancel)

let rec fold_left_s_n ~n f acc l =
  if n = 0 then Lwt.return (acc, l)
  else
    match l with
    | [] -> Lwt.return (acc, [])
    | x :: l ->
        let* acc = f acc x in
        (fold_left_s_n [@ocaml.tailcall]) f ~n:(n - 1) acc l

let rec find_map_s f = function
  | [] -> Lwt.return_none
  | x :: l ->
      Lwt.bind (f x) (function None -> find_map_s f l | r -> Lwt.return r)
