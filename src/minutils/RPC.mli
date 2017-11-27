(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

(** Typed RPC services: definition, binding and dispatch. *)


module Data : Resto.ENCODING with type 'a t = 'a Data_encoding.t
                              and type schema = Data_encoding.json_schema

include (module type of struct include Resto end)
include (module type of struct include RestoDirectory end)
module Directory : (module type of struct include RestoDirectory.MakeDirectory(Data) end)
module Service : (module type of struct include Directory.Service end)

(** Compatibility layer, to be removed ASAP. *)

type 'a directory = 'a Directory.t
type ('prefix, 'params, 'input, 'output) service =
  ([ `POST ], 'prefix, 'params, unit, 'input, 'output, unit) Service.t

val service:
  ?description: string ->
  input: 'input Data_encoding.t ->
  output: 'output Data_encoding.t ->
  ('prefix, 'params) Path.t ->
  ('prefix, 'params, 'input, 'output) service

type directory_descr = Data_encoding.json_schema Description.directory

val empty: 'a directory
val register:
  'prefix directory ->
  ('prefix, 'params, 'input, 'output) service ->
  ('params -> 'input -> [< ('output, unit) RestoDirectory.Answer.t ] Lwt.t) ->
  'prefix directory

val register0:
  unit directory ->
  (unit, unit, 'i, 'o) service ->
  ('i -> [< ('o, unit) Answer.t ] Lwt.t) ->
  unit directory

val register1:
  'prefix directory ->
  ('prefix, unit * 'a, 'i, 'o) service ->
  ('a -> 'i -> [< ('o, unit) Answer.t ] Lwt.t) ->
  'prefix directory

val register2:
  'prefix directory ->
  ('prefix, (unit * 'a) * 'b, 'i, 'o) service ->
  ('a -> 'b -> 'i -> [< ('o, unit) Answer.t ] Lwt.t) ->
  'prefix directory

val register_dynamic_directory1:
  ?descr:string ->
  'prefix directory ->
  ('prefix, unit * 'a) Path.path ->
  ('a -> (unit * 'a) directory Lwt.t) ->
  'prefix directory

val forge_request:
  (unit, 'params, 'input, _) service ->
  'params -> 'input -> MethMap.key * string list * Data_encoding.json

