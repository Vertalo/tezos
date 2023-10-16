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

module Token = struct
  type 'token t = Tez : Tez_repr.t t
end

type staker = Staker_repr.staker =
  | Single of Contract_repr.t * Signature.public_key_hash
  | Shared of Signature.public_key_hash

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

let token_of_balance : type token. token balance -> token Token.t = function
  | Contract _ -> Token.Tez
  | Block_fees -> Token.Tez
  | Deposits _ -> Token.Tez
  | Unstaked_deposits _ -> Token.Tez
  | Nonce_revelation_rewards -> Token.Tez
  | Attesting_rewards -> Token.Tez
  | Baking_rewards -> Token.Tez
  | Baking_bonuses -> Token.Tez
  | Storage_fees -> Token.Tez
  | Double_signing_punishments -> Token.Tez
  | Lost_attesting_rewards _ -> Token.Tez
  | Liquidity_baking_subsidies -> Token.Tez
  | Burned -> Token.Tez
  | Commitments _ -> Token.Tez
  | Bootstrap -> Token.Tez
  | Invoice -> Token.Tez
  | Initial_commitments -> Token.Tez
  | Minted -> Token.Tez
  | Frozen_bonds _ -> Token.Tez
  | Sc_rollup_refutation_punishments -> Token.Tez
  | Sc_rollup_refutation_rewards -> Token.Tez

let is_not_zero c = not (Compare.Int.equal c 0)

let compare_balance :
    type token1 token2. token1 balance -> token2 balance -> int =
 fun ba bb ->
  match (ba, bb) with
  | Contract ca, Contract cb -> Contract_repr.compare ca cb
  | Deposits sa, Deposits sb -> Staker_repr.compare_staker sa sb
  | Unstaked_deposits (sa, ca), Unstaked_deposits (sb, cb) ->
      Compare.or_else (Staker_repr.compare_staker sa sb) (fun () ->
          Cycle_repr.compare ca cb)
  | Lost_attesting_rewards (pkha, pa, ra), Lost_attesting_rewards (pkhb, pb, rb)
    ->
      let c = Signature.Public_key_hash.compare pkha pkhb in
      if is_not_zero c then c
      else
        let c = Compare.Bool.compare pa pb in
        if is_not_zero c then c else Compare.Bool.compare ra rb
  | Commitments bpkha, Commitments bpkhb ->
      Blinded_public_key_hash.compare bpkha bpkhb
  | Frozen_bonds (ca, ra), Frozen_bonds (cb, rb) ->
      let c = Contract_repr.compare ca cb in
      if is_not_zero c then c else Bond_id_repr.compare ra rb
  | _, _ ->
      let index : type token. token balance -> int = function
        | Contract _ -> 0
        | Block_fees -> 1
        | Deposits _ -> 2
        | Unstaked_deposits _ -> 3
        | Nonce_revelation_rewards -> 4
        | Attesting_rewards -> 5
        | Baking_rewards -> 6
        | Baking_bonuses -> 7
        | Storage_fees -> 8
        | Double_signing_punishments -> 9
        | Lost_attesting_rewards _ -> 10
        | Liquidity_baking_subsidies -> 11
        | Burned -> 12
        | Commitments _ -> 13
        | Bootstrap -> 14
        | Invoice -> 15
        | Initial_commitments -> 16
        | Minted -> 17
        | Frozen_bonds _ -> 18
        | Sc_rollup_refutation_punishments -> 19
        | Sc_rollup_refutation_rewards -> 20
        (* don't forget to add parameterized cases in the first part of the function *)
      in
      Compare.Int.compare (index ba) (index bb)

type 'token balance_update = Debited of 'token | Credited of 'token

type balance_and_update =
  | Ex_token : 'token balance * 'token balance_update -> balance_and_update

let is_zero_update = function Debited t | Credited t -> Tez_repr.(t = zero)

let conv_balance_update encoding =
  Data_encoding.conv
    (function Credited v -> `Credited v | Debited v -> `Debited v)
    (function `Credited v -> Credited v | `Debited v -> Debited v)
    encoding

let tez_balance_update_encoding =
  let open Data_encoding in
  def "operation_metadata.alpha.tez_balance_update"
  @@ obj1 (req "change" (conv_balance_update Tez_repr.balance_update_encoding))

let balance_and_update_encoding ~use_legacy_attestation_name =
  let open Data_encoding in
  let case = function
    | Tag tag ->
        (* The tag was used by old variant. It have been removed in
           protocol proposal O, it can be unblocked in the future. *)
        let tx_rollup_reserved_tag = [22; 23] in
        assert (
          not @@ List.exists (Compare.Int.equal tag) tx_rollup_reserved_tag) ;
        case (Tag tag)
    | _ as c -> case c
  in
  let tez_case ~title tag enc (proj : Tez_repr.t balance -> _ option) inj =
    case
      ~title
      tag
      (merge_objs enc tez_balance_update_encoding)
      (fun (Ex_token (balance, update)) ->
        let Tez = token_of_balance balance in
        proj balance |> Option.map (fun x -> (x, update)))
      (fun (x, update) -> Ex_token (inj x, update))
  in
  def
    (if use_legacy_attestation_name then
     "operation_metadata_with_legacy_attestation_name.alpha.balance_and_update"
    else "operation_metadata.alpha.balance_and_update")
  @@ union
       [
         tez_case
           (Tag 0)
           ~title:"Contract"
           (obj2
              (req "kind" (constant "contract"))
              (req "contract" Contract_repr.encoding))
           (function Contract c -> Some ((), c) | _ -> None)
           (fun ((), c) -> Contract c);
         tez_case
           (Tag 2)
           ~title:"Block_fees"
           (obj2
              (req "kind" (constant "accumulator"))
              (req "category" (constant "block fees")))
           (function Block_fees -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Block_fees);
         tez_case
           (Tag 4)
           ~title:"Deposits"
           (obj3
              (req "kind" (constant "freezer"))
              (req "category" (constant "deposits"))
              (req "staker" Staker_repr.staker_encoding))
           (function Deposits staker -> Some ((), (), staker) | _ -> None)
           (fun ((), (), staker) -> Deposits staker);
         tez_case
           (Tag 5)
           ~title:"Nonce_revelation_rewards"
           (obj2
              (req "kind" (constant "minted"))
              (req "category" (constant "nonce revelation rewards")))
           (function Nonce_revelation_rewards -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Nonce_revelation_rewards);
         (* 6 was for Double_signing_evidence_rewards that has been removed.
            https://gitlab.com/tezos/tezos/-/merge_requests/7758 *)
         tez_case
           (Tag 7)
           ~title:
             (if use_legacy_attestation_name then "Endorsing_rewards"
             else "Attesting_rewards")
           (obj2
              (req "kind" (constant "minted"))
              (req
                 "category"
                 (constant
                    (if use_legacy_attestation_name then "endorsing rewards"
                    else "attesting rewards"))))
           (function Attesting_rewards -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Attesting_rewards);
         tez_case
           (Tag 8)
           ~title:"Baking_rewards"
           (obj2
              (req "kind" (constant "minted"))
              (req "category" (constant "baking rewards")))
           (function Baking_rewards -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Baking_rewards);
         tez_case
           (Tag 9)
           ~title:"Baking_bonuses"
           (obj2
              (req "kind" (constant "minted"))
              (req "category" (constant "baking bonuses")))
           (function Baking_bonuses -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Baking_bonuses);
         tez_case
           (Tag 11)
           ~title:"Storage_fees"
           (obj2
              (req "kind" (constant "burned"))
              (req "category" (constant "storage fees")))
           (function Storage_fees -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Storage_fees);
         tez_case
           (Tag 12)
           ~title:"Double_signing_punishments"
           (obj2
              (req "kind" (constant "burned"))
              (req "category" (constant "punishments")))
           (function Double_signing_punishments -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Double_signing_punishments);
         tez_case
           (Tag 13)
           ~title:
             (if use_legacy_attestation_name then "Lost_endorsing_rewards"
             else "Lost_attesting_rewards")
           (obj5
              (req "kind" (constant "burned"))
              (req
                 "category"
                 (constant
                    (if use_legacy_attestation_name then
                     "lost endorsing rewards"
                    else "lost attesting rewards")))
              (req "delegate" Signature.Public_key_hash.encoding)
              (req "participation" Data_encoding.bool)
              (req "revelation" Data_encoding.bool))
           (function
             | Lost_attesting_rewards (d, p, r) -> Some ((), (), d, p, r)
             | _ -> None)
           (fun ((), (), d, p, r) -> Lost_attesting_rewards (d, p, r));
         tez_case
           (Tag 14)
           ~title:"Liquidity_baking_subsidies"
           (obj2
              (req "kind" (constant "minted"))
              (req "category" (constant "subsidy")))
           (function Liquidity_baking_subsidies -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Liquidity_baking_subsidies);
         tez_case
           (Tag 15)
           ~title:"Burned"
           (obj2
              (req "kind" (constant "burned"))
              (req "category" (constant "burned")))
           (function Burned -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Burned);
         tez_case
           (Tag 16)
           ~title:"Commitments"
           (obj3
              (req "kind" (constant "commitment"))
              (req "category" (constant "commitment"))
              (req "committer" Blinded_public_key_hash.encoding))
           (function Commitments bpkh -> Some ((), (), bpkh) | _ -> None)
           (fun ((), (), bpkh) -> Commitments bpkh);
         tez_case
           (Tag 17)
           ~title:"Bootstrap"
           (obj2
              (req "kind" (constant "minted"))
              (req "category" (constant "bootstrap")))
           (function Bootstrap -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Bootstrap);
         tez_case
           (Tag 18)
           ~title:"Invoice"
           (obj2
              (req "kind" (constant "minted"))
              (req "category" (constant "invoice")))
           (function Invoice -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Invoice);
         tez_case
           (Tag 19)
           ~title:"Initial_commitments"
           (obj2
              (req "kind" (constant "minted"))
              (req "category" (constant "commitment")))
           (function Initial_commitments -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Initial_commitments);
         tez_case
           (Tag 20)
           ~title:"Minted"
           (obj2
              (req "kind" (constant "minted"))
              (req "category" (constant "minted")))
           (function Minted -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Minted);
         tez_case
           (Tag 21)
           ~title:"Frozen_bonds"
           (obj4
              (req "kind" (constant "freezer"))
              (req "category" (constant "bonds"))
              (req "contract" Contract_repr.encoding)
              (req "bond_id" Bond_id_repr.encoding))
           (function Frozen_bonds (c, r) -> Some ((), (), c, r) | _ -> None)
           (fun ((), (), c, r) -> Frozen_bonds (c, r));
         tez_case
           (Tag 24)
           ~title:"Smart_rollup_refutation_punishments"
           (obj2
              (req "kind" (constant "burned"))
              (req "category" (constant "smart_rollup_refutation_punishments")))
           (function
             | Sc_rollup_refutation_punishments -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Sc_rollup_refutation_punishments);
         tez_case
           (Tag 25)
           ~title:"Smart_rollup_refutation_rewards"
           (obj2
              (req "kind" (constant "minted"))
              (req "category" (constant "smart_rollup_refutation_rewards")))
           (function
             | Sc_rollup_refutation_rewards -> Some ((), ()) | _ -> None)
           (fun ((), ()) -> Sc_rollup_refutation_rewards);
         tez_case
           (Tag 26)
           ~title:"Unstaked_deposits"
           (obj4
              (req "kind" (constant "freezer"))
              (req "category" (constant "unstaked_deposits"))
              (req "staker" Staker_repr.staker_encoding)
              (req "cycle" Cycle_repr.encoding))
           (function
             | Unstaked_deposits (staker, cycle) -> Some ((), (), staker, cycle)
             | _ -> None)
           (fun ((), (), staker, cycle) -> Unstaked_deposits (staker, cycle));
       ]

let balance_and_update_encoding_with_legacy_attestation_name =
  balance_and_update_encoding ~use_legacy_attestation_name:true

let balance_and_update_encoding =
  balance_and_update_encoding ~use_legacy_attestation_name:false

type update_origin =
  | Block_application
  | Protocol_migration
  | Subsidy
  | Simulation

let compare_update_origin oa ob =
  let index o =
    match o with
    | Block_application -> 0
    | Protocol_migration -> 1
    | Subsidy -> 2
    | Simulation -> 3
  in
  Compare.Int.compare (index oa) (index ob)

let update_origin_encoding =
  let open Data_encoding in
  def "operation_metadata.alpha.update_origin"
  @@ obj1 @@ req "origin"
  @@ union
       [
         case
           (Tag 0)
           ~title:"Block_application"
           (constant "block")
           (function Block_application -> Some () | _ -> None)
           (fun () -> Block_application);
         case
           (Tag 1)
           ~title:"Protocol_migration"
           (constant "migration")
           (function Protocol_migration -> Some () | _ -> None)
           (fun () -> Protocol_migration);
         case
           (Tag 2)
           ~title:"Subsidy"
           (constant "subsidy")
           (function Subsidy -> Some () | _ -> None)
           (fun () -> Subsidy);
         case
           (Tag 3)
           ~title:"Simulation"
           (constant "simulation")
           (function Simulation -> Some () | _ -> None)
           (fun () -> Simulation);
       ]

type balance_update_item =
  | Balance_update_item :
      Tez_repr.t balance * Tez_repr.t balance_update * update_origin
      -> balance_update_item

let item balance balance_update update_origin =
  Balance_update_item (balance, balance_update, update_origin)

let item_encoding_with_legacy_attestation_name =
  let open Data_encoding in
  conv
    (function
      | Balance_update_item (balance, balance_update, update_origin) ->
          (Ex_token (balance, balance_update), update_origin))
    (fun (Ex_token (balance, balance_update), update_origin) ->
      let Tez = token_of_balance balance in
      Balance_update_item (balance, balance_update, update_origin))
    (merge_objs
       balance_and_update_encoding_with_legacy_attestation_name
       update_origin_encoding)

let item_encoding =
  let open Data_encoding in
  conv
    (function
      | Balance_update_item (balance, balance_update, update_origin) ->
          (Ex_token (balance, balance_update), update_origin))
    (fun (Ex_token (balance, balance_update), update_origin) ->
      let Tez = token_of_balance balance in
      Balance_update_item (balance, balance_update, update_origin))
    (merge_objs balance_and_update_encoding update_origin_encoding)

type balance_updates = balance_update_item list

let balance_updates_encoding_with_legacy_attestation_name =
  let open Data_encoding in
  def "operation_metadata_with_legacy_attestation_name.alpha.balance_updates"
  @@ list item_encoding_with_legacy_attestation_name

let balance_updates_encoding =
  let open Data_encoding in
  def "operation_metadata.alpha.balance_updates" @@ list item_encoding

module BalanceMap = struct
  include Map.Make (struct
    type t = Tez_repr.t balance * update_origin

    let compare (ba, ua) (bb, ub) =
      let c = compare_balance ba bb in
      if is_not_zero c then c else compare_update_origin ua ub
  end)

  let update_r key (f : 'a option -> 'b option tzresult) map =
    let open Result_syntax in
    let* v_opt = f (find key map) in
    match v_opt with
    | Some v -> return (add key v map)
    | None -> return (remove key map)
end

let group_balance_updates balance_updates =
  let open Result_syntax in
  let* map =
    List.fold_left_e
      (fun acc (Balance_update_item (b, update, o)) ->
        (* Do not do anything if the update is zero *)
        if is_zero_update update then return acc
        else
          BalanceMap.update_r
            (b, o)
            (function
              | None -> return_some update
              | Some balance -> (
                  match (balance, update) with
                  | Credited a, Debited b | Debited b, Credited a ->
                      (* Remove the binding since it just fell down to zero *)
                      if Tez_repr.(a = b) then return_none
                      else if Tez_repr.(a > b) then
                        let* update = Tez_repr.(a -? b) in
                        return_some (Credited update)
                      else
                        let* update = Tez_repr.(b -? a) in
                        return_some (Debited update)
                  | Credited a, Credited b ->
                      let* update = Tez_repr.(a +? b) in
                      return_some (Credited update)
                  | Debited a, Debited b ->
                      let* update = Tez_repr.(a +? b) in
                      return_some (Debited update)))
            acc)
      BalanceMap.empty
      balance_updates
  in
  return
    (BalanceMap.fold
       (fun (b, o) u acc -> Balance_update_item (b, u, o) :: acc)
       map
       [])
