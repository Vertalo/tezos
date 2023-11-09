(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2022-2023 TriliTech <contact@trili.tech>                    *)
(* Copyright (c) 2023 Marigold <contact@marigold.dev>                        *)
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

(** Helpers built upon the Sc_rollup_node and Sc_rollup_client *)

(*
  SC tests may contain arbitrary/generated bytes in external messages,
  and captured deposits/withdrawals contain byte sequences that change
  for both proofs and contract addresses.
 *)
let replace_variables string =
  string
  |> replace_string ~all:true (rex "0x01\\w{40}00") ~by:"[MICHELINE_KT1_BYTES]"
  |> replace_string ~all:true (rex "0x.*") ~by:"[SMART_ROLLUP_BYTES]"
  |> replace_string
       ~all:true
       (rex "hex\\:\\[\".*?\"\\]")
       ~by:"[SMART_ROLLUP_EXTERNAL_MESSAGES]"
  |> Tezos_regression.replace_variables

let hooks = Tezos_regression.hooks_custom ~replace_variables ()

let hex_encode (input : string) : string =
  match Hex.of_string input with `Hex s -> s

let load_kernel_file
    ?(base = "src/proto_alpha/lib_protocol/test/integration/wasm_kernel") name :
    string =
  let open Tezt.Base in
  let kernel_file = project_root // base // name in
  read_file kernel_file

(* [read_kernel filename] reads binary encoded WebAssembly module (e.g. `foo.wasm`)
   and returns a hex-encoded Wasm PVM boot sector, suitable for passing to
   [originate_sc_rollup].
*)
let read_kernel ?base name : string =
  hex_encode (load_kernel_file ?base (name ^ ".wasm"))

module Installer_kernel_config = struct
  type move_args = {from : string; to_ : string}

  type reveal_args = {hash : string; to_ : string}

  type set_args = {value : string; to_ : string}

  type instr = Move of move_args | Reveal of reveal_args | Set of set_args

  type t = instr list

  let instr_to_yaml = function
    | Move {from; to_} -> sf {|  - move:
      from: %s
      to: %s
|} from to_
    | Reveal {hash; to_} -> sf {|  - reveal: %s
    to: %s
|} hash to_
    | Set {value; to_} ->
        sf {|  - set:
      value: %s
      to: %s
|} value to_

  let to_yaml t =
    "instructions:\n" ^ String.concat "" (List.map instr_to_yaml t)
end

(* Testing the installation of a larger kernel, with e2e messages.

   When a kernel is too large to be originated directly, we can install
   it by using the 'reveal_installer' kernel. This leverages the reveal
   preimage+DAC mechanism to install the tx kernel.
*)
let prepare_installer_kernel_gen ?runner
    ?(base_installee =
      "src/proto_alpha/lib_protocol/test/integration/wasm_kernel")
    ~preimages_dir ?(display_root_hash = false) ?config installee =
  let open Tezt.Base in
  let open Lwt.Syntax in
  let installer = installee ^ "-installer.hex" in
  let output = Temp.file installer in
  let installee = (project_root // base_installee // installee) ^ ".wasm" in
  let setup_file_args =
    match config with
    | Some config ->
        let setup_file = Temp.file "setup-config.yaml" in
        Base.write_file
          setup_file
          ~contents:(Installer_kernel_config.to_yaml config) ;
        ["--setup-file"; setup_file]
    | None -> []
  in
  let display_root_hash_arg =
    if display_root_hash then ["--display-root-hash"] else []
  in
  let process =
    Process.spawn
      ?runner
      ~name:installer
      (project_root // "smart-rollup-installer")
      ([
         "get-reveal-installer";
         "--upgrade-to";
         installee;
         "--output";
         output;
         "--preimages-dir";
         preimages_dir;
       ]
      @ display_root_hash_arg @ setup_file_args)
  in
  let+ installer_output =
    Runnable.run
    @@ Runnable.{value = process; run = Process.check_and_read_stdout}
  in
  let root_hash =
    if display_root_hash then installer_output =~* rex "ROOT_HASH: ?(\\w*)"
    else None
  in
  (read_file output, root_hash)

let prepare_installer_kernel ?runner ?base_installee ~preimages_dir ?config
    installee =
  let open Lwt.Syntax in
  let+ output, _ =
    prepare_installer_kernel_gen
      ?runner
      ?base_installee
      ~preimages_dir
      ?config
      installee
  in
  output

let default_boot_sector_of ~kind =
  match kind with
  | "arith" -> ""
  | "wasm_2_0_0" -> Constant.wasm_echo_kernel_boot_sector
  | kind -> raise (Invalid_argument kind)

let make_parameter name = function
  | None -> []
  | Some value -> [([name], `Int value)]

let make_bool_parameter name = function
  | None -> []
  | Some value -> [([name], `Bool value)]

let setup_l1 ?bootstrap_smart_rollups ?commitment_period ?challenge_window
    ?timeout ?whitelist_enable protocol =
  let parameters =
    make_parameter "smart_rollup_commitment_period_in_blocks" commitment_period
    @ make_parameter "smart_rollup_challenge_window_in_blocks" challenge_window
    @ make_parameter "smart_rollup_timeout_period_in_blocks" timeout
    @ (if Protocol.number protocol >= 19 then
       make_bool_parameter "smart_rollup_private_enable" whitelist_enable
      else [])
    @ [(["smart_rollup_arith_pvm_enable"], `Bool true)]
  in
  let base = Either.right (protocol, None) in
  let* parameter_file =
    Protocol.write_parameter_file ?bootstrap_smart_rollups ~base parameters
  in
  let nodes_args =
    Node.[Synchronisation_threshold 0; History_mode Archive; No_bootstrap_peers]
  in
  Client.init_with_protocol ~parameter_file `Client ~protocol ~nodes_args ()

(** This helper injects an SC rollup origination via octez-client. Then it
    bakes to include the origination in a block. It returns the address of the
    originated rollup *)
let originate_sc_rollup ?hooks ?(burn_cap = Tez.(of_int 9999999)) ?whitelist
    ?(alias = "rollup") ?(src = Constant.bootstrap1.alias) ~kind
    ?(parameters_ty = "string") ?(boot_sector = default_boot_sector_of ~kind)
    client =
  let* sc_rollup =
    Client.Sc_rollup.(
      originate
        ?hooks
        ~burn_cap
        ?whitelist
        ~alias
        ~src
        ~kind
        ~parameters_ty
        ~boot_sector
        client)
  in
  let* () = Client.bake_for_and_wait client in
  return sc_rollup

let last_cemented_commitment_hash_with_level ~sc_rollup client =
  let* json =
    RPC.Client.call client
    @@ RPC
       .get_chain_block_context_smart_rollups_smart_rollup_last_cemented_commitment_hash_with_level
         sc_rollup
  in
  let hash = JSON.(json |-> "hash" |> as_string) in
  let level = JSON.(json |-> "level" |> as_int) in
  return (hash, level)

let genesis_commitment ~sc_rollup tezos_client =
  let* genesis_info =
    RPC.Client.call ~hooks tezos_client
    @@ RPC.get_chain_block_context_smart_rollups_smart_rollup_genesis_info
         sc_rollup
  in
  let genesis_commitment_hash =
    JSON.(genesis_info |-> "commitment_hash" |> as_string)
  in
  let* json =
    RPC.Client.call ~hooks tezos_client
    @@ RPC.get_chain_block_context_smart_rollups_smart_rollup_commitment
         ~sc_rollup
         ~hash:genesis_commitment_hash
         ()
  in
  match Sc_rollup_client.commitment_from_json json with
  | None -> failwith "genesis commitment have been removed"
  | Some commitment -> return commitment

let call_rpc ~smart_rollup_node ~service =
  let open Runnable.Syntax in
  let url =
    Printf.sprintf "%s/%s" (Sc_rollup_node.endpoint smart_rollup_node) service
  in
  let*! response = RPC.Curl.get url in
  return response