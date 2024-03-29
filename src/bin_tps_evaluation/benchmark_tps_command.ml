(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

open Constants

(** The level at which the benchmark starts. We wait till level 3 because we
   need to inject transactions that target already decided blocks. In
   Tenderbake, a block is decided when there are 2 blocks on top of it. We
   cannot target genesis (level 0) because it is not yet in the right
   protocol, thus we wait till level 1 is decided, i.e. we want level 3. *)
let benchmark_starting_level = 3

(** Print out the file at [path] to the stdout. *)
let print_out_file path =
  let open Lwt_io in
  with_file ~mode:Input path (fun ic ->
      read ic >>= fun str ->
      write stdout str >>= fun () ->
      write stdout "\n\n" >>= fun () -> flush stdout)

(** Get a list of hashes of the given number of most recent blocks. *)
let get_blocks blocks_total client =
  let path = ["chains"; "main"; "blocks"] in
  let query_string = [("length", Int.to_string blocks_total)] in
  Client.rpc ~query_string GET path client >|= fun json ->
  List.map JSON.as_string (JSON.as_list (JSON.geti 0 json))

(** Get the total number of injected transactions. *)
let get_total_injected_transactions () =
  let tmp_dir = Filename.get_temp_dir_name () in

  (* Choose the most recently created file. *)
  let operations_file =
    Sys.readdir tmp_dir |> Array.to_list
    |> List.filter_map (fun file ->
           if
             String.has_prefix
               ~prefix:"client-stresstest-injected_operations"
               file
             && Filename.extension file = ".json"
           then
             let f = Filename.concat tmp_dir file in
             Some (Unix.stat f, f)
           else None)
    |> List.sort (fun (a1, _) (b1, _) -> Unix.(compare b1.st_ctime a1.st_ctime))
    |> List.map snd |> List.hd
  in

  match operations_file with
  | None ->
      Format.kasprintf
        Stdlib.failwith
        "The injected operations json file was not found. It should have been \
         generated by the tezos-client stresstest command@."
  | Some f ->
      let block_transactions = JSON.as_list (JSON.parse_file f) in

      List.fold_left
        (fun a b ->
          match
            List.assoc ~equal:String.equal "operation_hashes" (JSON.as_object b)
          with
          | Some v -> List.length (JSON.as_list v) + a
          | None -> a)
        0
        block_transactions

(** Get the number of applied transactions in the block with the given
    hash. *)
let get_total_applied_transactions_for_block block client =
  (*
    N.B. Grouping of the operations by validation passes:
    - 0: consensus
    - 1: governance (voting)
    - 2: anonymous (denounciations)
    - 3: manager operations

    We are interested in 3, so we select that.
   *)
  let path = ["chains"; "main"; "blocks"; block; "operation_hashes"; "3"] in
  Client.rpc GET path client >|= fun json -> List.length (JSON.as_list json)

(** The entry point of the benchmark. *)
let run_benchmark ~lift_protocol_limits ~provided_tps_of_injection
    ~accounts_total ~blocks_total ~average_block_path () =
  Log.info "Tezos TPS benchmark" ;
  Log.info "Protocol: %s" (Protocol.name protocol) ;
  Log.info "Total number of accounts to use: %d" accounts_total ;
  Log.info "Blocks to bake: %d" blocks_total ;
  Protocol.write_parameter_file
    ~base:(Either.right (protocol, Some protocol_constants))
    (if lift_protocol_limits then
     [
       (* We're using the maximum representable number. (2 ^ 31 - 1) *)
       (["hard_gas_limit_per_block"], Some {|"2147483647"|});
       (["hard_gas_limit_per_operation"], Some {|"2147483647"|});
     ]
    else [])
  >>= fun parameter_file ->
  Log.info "Spinning up the network..." ;
  (* For now we disable operations precheck, but ideally we should
     pre-populate enough bootstrap accounts and do 1 transaction per
     account per block. *)
  Client.init_with_protocol
    ~nodes_args:
      Node.
        [
          Connections 0; Synchronisation_threshold 0; Disable_operations_precheck;
        ]
    ~parameter_file
    ~timestamp_delay:0.0
    `Client
    ~protocol
    ()
  >>= fun (node, client) ->
  Average_block.load average_block_path >>= fun average_block ->
  Average_block.check_for_unknown_smart_contracts average_block >>= fun () ->
  Baker.init ~protocol ~delegates node client >>= fun _baker ->
  Log.info "Originating smart contracts" ;
  Client.stresstest_originate_smart_contracts originating_bootstrap client
  >>= fun () ->
  Log.info "Waiting to reach the next level" ;
  Node.wait_for_level node 2 >>= fun _ ->
  (* It is important to give the chain time to include the smart contracts
     we have originated before we run gas estimations. *)
  Client.stresstest_estimate_gas client >>= fun transaction_costs ->
  let average_transaction_cost =
    Gas.average_transaction_cost transaction_costs average_block
  in
  Log.info "Average transaction cost: %d" average_transaction_cost ;
  Log.info "Using the parameter file: %s" parameter_file ;
  print_out_file parameter_file >>= fun () ->
  Log.info "Waiting to reach level %d" benchmark_starting_level ;
  Node.wait_for_level node benchmark_starting_level >>= fun _ ->
  let bench_start = Unix.gettimeofday () in
  Log.info "The benchmark has been started" ;
  (* It is important to use a good estimate of max possible TPS that is
     theoretically achievable. If we send operations with lower TPS than
     this we risk obtaining a sub-estimated value for TPS. If we use a
     higher TPS than the maximal possible we risk to saturate the mempool
     and again obtain a less-than-perfect estimation in the end. *)
  let target_tps_of_injection =
    match provided_tps_of_injection with
    | Some tps_value -> tps_value
    | None ->
        (* This is a high enough value (not realistically achievable
           by the benchmark) so we're not limited by it. *)
        if lift_protocol_limits then max_int
        else
          Gas.deduce_tps
            ~protocol
            ~protocol_constants
            ~average_transaction_cost
            ()
  in
  let (regular_transaction_fee, regular_transaction_gas_limit) =
    Gas.deduce_fee_and_gas_limit transaction_costs.regular
  in
  let smart_contract_parameters =
    Gas.calculate_smart_contract_parameters average_block transaction_costs
  in
  let client_stresstest_process =
    Client.spawn_stresstest
      ~fee:regular_transaction_fee
      ~gas_limit:regular_transaction_gas_limit
      ~tps:
        target_tps_of_injection
        (* The stresstest command allows a small probability of creating
           new accounts along the way. We do not want that, so we set it to
           0. *)
      ~fresh_probability:0.0
      ~smart_contract_parameters
      client
  in
  Node.wait_for_level node (benchmark_starting_level + blocks_total)
  >>= fun _level ->
  Process.terminate client_stresstest_process ;
  Process.wait client_stresstest_process >>= fun _ ->
  let bench_end = Unix.gettimeofday () in
  let bench_duration = bench_end -. bench_start in
  Log.info "Produced %d block(s) in %.2f seconds" blocks_total bench_duration ;
  get_blocks blocks_total client >>= fun produced_block_hashes ->
  let total_injected_transactions = get_total_injected_transactions () in
  let total_applied_transactions = ref 0 in
  let handle_one_block block_hash =
    get_total_applied_transactions_for_block block_hash client
    >|= fun applied_transactions ->
    total_applied_transactions :=
      !total_applied_transactions + applied_transactions ;
    Log.info "%s -> %d" block_hash applied_transactions
  in
  List.iter_s handle_one_block (List.rev produced_block_hashes) >>= fun () ->
  Log.info "Total applied transactions: %d" !total_applied_transactions ;
  Log.info "Total injected transactions: %d" total_injected_transactions ;
  let empirical_tps =
    Float.of_int !total_applied_transactions /. bench_duration
  in
  let de_facto_tps_of_injection =
    Float.of_int total_injected_transactions /. bench_duration
  in
  Log.info "TPS of injection (target): %d" target_tps_of_injection ;
  Log.info "TPS of injection (de facto): %.2f" de_facto_tps_of_injection ;
  Log.info "Empirical TPS: %.2f" empirical_tps ;
  Node.terminate ~kill:true node >>= fun () ->
  return (de_facto_tps_of_injection, empirical_tps)

let regression_handling defacto_tps_of_injection empirical_tps
    lifted_protocol_limits ~previous_count =
  let lifted_protocol_limits_tag = string_of_bool lifted_protocol_limits in
  let save_and_check =
    Long_test.measure_and_check_regression
      ~previous_count
      ~minimum_previous_count:previous_count
      ~stddev:false
      ~repeat:1
      ~tags:[("lifted_protocol_limits", lifted_protocol_limits_tag)]
  in
  let* () =
    save_and_check "defacto_tps_of_injection" @@ fun () ->
    defacto_tps_of_injection
  in
  save_and_check "empirical_tps" @@ fun () -> empirical_tps

module Term = struct
  let accounts_total_arg =
    let open Cmdliner in
    let doc = "The number of bootstrap accounts to use in the benchmark" in
    let docv = "ACCOUNTS_TOTAL" in
    Arg.(value & opt int 5 & info ["accounts-total"] ~docv ~doc)

  let blocks_total_arg =
    let open Cmdliner in
    let doc = "The number of blocks to bake during the benchmark" in
    let docv = "BLOCKS_TOTAL" in
    Arg.(value & opt int 10 & info ["blocks-total"] ~docv ~doc)

  let average_block_path_arg =
    let open Cmdliner in
    let doc = "Path to the file with description of the average block" in
    let docv = "AVERAGE_BLOCK_PATH" in
    Arg.(value & opt (some string) None & info ["average-block"] ~docv ~doc)

  let lift_protocol_limits_arg =
    let open Cmdliner in
    let doc =
      "Remove any protocol settings that may limit the maximum achievable TPS"
    in
    let docv = "LIFT_PROTOCOL_LIMITS" in
    Arg.(value (flag & info ["lift-protocol-limits"] ~docv ~doc))

  let tps_of_injection_arg =
    let open Cmdliner in
    let doc = "The injection TPS value that we should use" in
    let docv = "TPS_OF_INJECTION" in
    Arg.(value & opt (some int) None & info ["tps-of-injection"] ~docv ~doc)

  let tezt_args =
    let open Cmdliner in
    let doc =
      "Extra arguments after -- to be passed directly to Tezt. Contains `-i` \
       by default to display info log level."
    in
    let docv = "TEZT_ARGS" in
    Arg.(value & pos_all string [] & info [] ~docv ~doc)

  let previous_count_arg =
    let open Cmdliner in
    let doc =
      "The number of previously recorded samples that must be compared to the \
       result of this benchmark"
    in
    let docv = "PREVIOUS_SAMPLE_COUNT" in
    Arg.(
      value & opt int 10 & info ["regression-previous-sample-count"] ~docv ~doc)

  let term =
    let process accounts_total blocks_total average_block_path
        lift_protocol_limits provided_tps_of_injection tezt_args previous_count
        =
      (try Cli.init ~args:("-i" :: tezt_args) ()
       with Arg.Help help_str ->
         Format.eprintf "%s@." help_str ;
         exit 0) ;
      Long_test.init () ;
      let executors = Long_test.[x86_executor1] in
      Long_test.register
        ~__FILE__
        ~title:"tezos_tps_benchmark"
        ~tags:[]
        ~timeout:(Long_test.Minutes 60)
        ~executors
        (fun () ->
          let* (defacto_tps_of_injection, empirical_tps) =
            run_benchmark
              ~lift_protocol_limits
              ~provided_tps_of_injection
              ~accounts_total
              ~blocks_total
              ~average_block_path
              ()
          in
          regression_handling
            defacto_tps_of_injection
            empirical_tps
            lift_protocol_limits
            ~previous_count) ;
      Test.run () ;
      `Ok ()
    in
    let open Cmdliner.Term in
    ret
      (const process $ accounts_total_arg $ blocks_total_arg
     $ average_block_path_arg $ lift_protocol_limits_arg $ tps_of_injection_arg
     $ tezt_args $ previous_count_arg)
end

module Manpage = struct
  let command_description =
    "Run the benchmark and print out the results on stdout"

  let description = [`S "DESCRIPTION"; `P command_description]

  let man = description

  let info = Cmdliner.Term.info ~doc:command_description ~man "benchmark-tps"
end

let cmd = (Term.term, Manpage.info)
