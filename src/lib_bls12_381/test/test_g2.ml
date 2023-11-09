(*****************************************************************************)
(*                                                                           *)
(* Copyright (c) 2020-2021 Danny Willems <be.danny.willems@gmail.com>        *)
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

let () = Random.self_init ()

module G2 = Bls12_381.G2
module ValueGeneration = Test_ec_make.MakeValueGeneration (G2)
module IsZero = Test_ec_make.MakeIsZero (G2)
module Equality = Test_ec_make.MakeEquality (G2)
module ECProperties = Test_ec_make.MakeECProperties (G2)
module BulkOperations = Test_ec_make.MakeBulkOperations (G2)
module InplaceOperations = Test_ec_make.MakeInplaceOperations (G2)

module Memory = struct
  let test_copy () =
    let x = Bls12_381.G2.random () in
    let y = Bls12_381.G2.copy x in
    assert (Bls12_381.G2.eq x y)

  let test_size_in_memory () =
    match Sys.backend_type with
    | Native | Bytecode -> assert (Bls12_381.G2.size_in_memory = 304)
    | Other _ -> ()

  let get_tests () =
    let txt = "Memory" in
    let open Alcotest in
    ( txt,
      [
        test_case "copy" `Quick (Utils.repeat 100 test_copy);
        test_case "size in memory" `Quick test_size_in_memory;
      ] )
end

module Constructors = struct
  let test_of_z_one () =
    (* https://github.com/zcash/librustzcash/blob/0.1.0/pairing/src/bls12_381/fq.rs#L18 *)
    let x =
      ( Z.of_string
          "352701069587466618187139116011060144890029952792775240219908644239793785735715026873347600343865175952761926303160",
        Z.of_string
          "3059144344244213709971259814753781636986470325476647558659373206291635324768958432433509563104347017837885763365758"
      )
    in
    let y =
      ( Z.of_string
          "1985150602287291935568054521177171638300868978215655730859378665066344726373823718423869104263333984641494340347905",
        Z.of_string
          "927553665492332455747201965776037880757740193453592970025027978793976877002675564980949289727957565575433344219582"
      )
    in
    let g = G2.of_z_opt ~x ~y in
    match g with Some g -> assert (G2.eq G2.one g) | None -> assert false

  let test_vectors_random_points_not_on_curve () =
    let x = (Z.of_string "90809235435", Z.of_string "09809345809345809") in
    let y =
      (Z.of_string "8090843059809345", Z.of_string "908098039459089345")
    in
    match G2.of_z_opt ~x ~y with Some _ -> assert false | None -> assert true

  let get_tests () =
    let open Alcotest in
    ( "From Z elements",
      [
        test_case "one (generator)" `Quick test_of_z_one;
        test_case
          "random points not on curve"
          `Quick
          test_vectors_random_points_not_on_curve;
      ] )
end

module UncompressedRepresentation = struct
  let test_uncompressed_zero_has_first_byte_at_64 () =
    assert (int_of_char (Bytes.get G2.(to_bytes zero) 0) = 64)

  let test_uncompressed_random_has_first_byte_strictly_lower_than_64 () =
    assert (int_of_char (Bytes.get G2.(to_bytes (random ())) 0) < 64)

  let test_of_bytes_checks_the_point_is_in_the_prime_subgroup () =
    (* These elements have been generated by bls12-381-unix-blst, commit
       0bea1bf03a7633a4fbf6d551223c6b44a9452acc, by removing the multiplication
       by the cofactor in the random generator. It can be verified the elements
       are not in the prime subgroup by checking multiplying by Fr.order does
       not give zero. *)
    let test_vectors =
      [
        "07da246233ad216e60ee03070a0916154ae9f9dc23310c1191dfb4e277fc757f58a5cf5bdf7a9f322775143c37539cb90798205fd56217b682d5656f7ac7bc0da111dee59d3f863f1b040be659eda7941afb9f1bc5d0fe2beb5e2385e2cfe9ee18dde04e8b71e984b935b234563026f65b83c7e32034622af59ebd51c98ed99ad66bcffc710f009cff4c3752dfb93ec8177db1c1f42a6cc6c3f30fdd14dcaf1078a5df9bae729ba1f3b5716c0f54a89bda7a77417b9190fe054860e29454a03c";
        "1112717bbcd089ea99e8216eab455ea5cd462b0b3e3530303b83477f8e1bb7abca269fec10b3eb998f7f6fd1799d58ff11ed0a53bf75f91d2bf73d11bd52d061f401ac6a6ec0ef4a163e480bac85e75b97cb556f500057b9ef4b28bfe196791d1104428a522394320e59598746623843bf09c5a98649f954a83540cd73a853b5d9cdf15e4c7e3e865eab522b1aded1900c878821dc93161c3f58937698c962b2e78447a20e869eb5f25ed7d603b5c6597b191350e78079ee4d88a90b26e0e005";
        "06e5fa411047d9632c95747bea64d973757904c935ac0741b9eeefa2c7c4e439baf1d2c1e8633ba6c884ed9fdf1ffbdd129a32c046f355c5126254973115d6df32904498db6ca959d5bf1869f235be4c0e60fc334ed493f864476907cadfef2c007372c32dea649d4f55aebbbbb1253ebd704394c7158cf552669aa0c6eca84004979f2d2298e135199c4cbb3cf4389103489f9ee6992adefb74b1256c1e0ab1fe084942eb6da73cfafc93af113acc4d27702ad20d45f6d27e2efbb78bdc0990";
        "08c83e90520a5ea31733cc01e3589e10b2ed755e2faade29199f97645fbf73f52b29297c22a3b1c4fcd3379bceeec832091df6fb3b9d23f04e8267fc41e578002484155562e70f488c2a4c6b11522c66736bc977755c257478f3022656abb63002f62faa42476bccd9c2dc795ff4377cf2d3bad318036b17b29dc7b8ff54bc43c20deb3012ccde6542f7c6ba9b5c747c12f57a5dda59b4aad634c79d37933982edc5025d47927727c731fd6420e1f81d46376702ea327bb8f3f36d509d5b5175";
        "025099811f52ad463c762197466c476a03951afdb3f0a457efa2b9475376652fba7b2d56f3184dad540a234d471c53a113203f73dd661694586c75d9c418d34cd16504356253e3ba4618f61cbee02880a43efeacb8f9fe1fdc84ceec4f780ba219bc60a48811c801bea1ac9b1684d25e41ec273e232cfeda31ba0b3b5e75e4390d378784531120f3488c2618157a05cd0ed9fc24d3064a9e1dfb2a7177462b0a6538575f529a3bae63058bdecc7b371295f9cb53c505722f2a43ea73687bec8f";
        "190f5e1d200d1b9ab842c516ce50992730917a8b2e95ee1a4b830d7d9507c6846ace7a0eed8831a8d1f1e233cd24581215fe8fe85a99f4ca3fe046dba8ac6377fc3c10d73fa94b25c2d534d7a587a507b498754a2534cd85777b2a7f2978eec6076f8ea2cc632f47afbb6a428c2ba646adf12985d9387f4977240781bb1569bcb4fccca9158b18c38f316e097eea141202953692fea33a80953a3796a2cf6430e32da4e2ef6577b8a347e8ef2eba326e217e70ad94b111945699c5ee8f253bf1";
        "029415562a1d18b11ec8ab2e0b347a9417f9e904cf25f9b1dc40f235507814371fb4568cc1070a0b8c7baf39e0039d1e0b49d4352b095883ccc262e23d8651c49c39c06d0a920d40b2765d550a78c4c1940c8a2b6843a0063402c169f079f0ae144d1214376fd9c1d96d2e4744dfc64010f9f2ca4b8040d1e2be337f13526ee3dc70143578d90c85ba50748d013f5fc700cb0b25adfaca4f0f2c0f38da43b2b7ef292d710fb6735d353165c3aed9eca3b12dfab1b7268bba5193fb75cd44123a";
        "0a257ed6d95cb226c3eb57218bd075ba27164fc1b972c4230ee70c7b81c89d38253ccf7ed2896aa5eb3d9fd6021fac000e368080e705f2a65c919539e2d28e6dd1117296b4210fd56db8d96891f8586bd333e9c47f838ed436659a1dafaee16c043bab234f547ad93f0a1c6d508a7bdb58ebb23ff1b0717b886bfebc952b117fb3c2a0630353d2efeefedf59be128f140da32540640b4a5ad4799bf2a23bacb8c60abef281d24b584a5fe056ebc946a98987e070b32a4c7c9cdb39b37b7776b5";
      ]
    in
    List.iter
      (fun p_str ->
        try
          let p_bytes = Hex.to_bytes (`Hex p_str) in
          ignore @@ Bls12_381.G2.of_bytes_exn p_bytes ;
          assert false
        with Bls12_381.G2.Not_on_curve _p_bytes -> ())
      test_vectors ;
    List.iter
      (fun p_str ->
        let p_bytes = Hex.to_bytes (`Hex p_str) in
        assert (Option.is_none (Bls12_381.G2.of_bytes_opt p_bytes)))
      test_vectors

  let test_of_bytes_exn_and_opt_do_not_accept_compressed_bytes_representation ()
      =
    let x = Bls12_381.G2.random () in
    let x_compressed_bytes = Bls12_381.G2.to_compressed_bytes x in
    assert (Option.is_none (Bls12_381.G2.of_bytes_opt x_compressed_bytes)) ;
    try
      ignore @@ Bls12_381.G2.of_bytes_exn x_compressed_bytes ;
      assert false
    with Bls12_381.G2.Not_on_curve _b -> ()

  let get_tests () =
    let open Alcotest in
    ( "Representation of G2 Uncompressed",
      [
        test_case
          "zero has first byte at 64"
          `Quick
          test_uncompressed_zero_has_first_byte_at_64;
        test_case
          "of_bytes_[opt/exn] verifies the point is in the prime subgroup"
          `Quick
          test_of_bytes_checks_the_point_is_in_the_prime_subgroup;
        test_case
          "of_bytes_opt/exn do not accept compressed bytes representation"
          `Quick
          (Utils.repeat
             1000
             test_of_bytes_exn_and_opt_do_not_accept_compressed_bytes_representation);
        test_case
          "random has first byte strictly lower than 64"
          `Quick
          (Utils.repeat
             1000
             test_uncompressed_random_has_first_byte_strictly_lower_than_64);
      ] )
end

module CompressedRepresentation = struct
  include Test_ec_make.MakeCompressedRepresentation (G2)

  let test_vectors () =
    let vectors =
      [
        ( Hex.to_bytes
            (`Hex
              "93e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"),
          G2.to_compressed_bytes G2.one );
        ( Hex.to_bytes
            (`Hex
              "c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
          G2.to_compressed_bytes G2.zero );
      ]
    in
    List.iter
      (fun (expected_bytes, computed_bytes) ->
        assert (Bytes.equal expected_bytes computed_bytes))
      vectors

  (* Random points generated for regression tests ```ocaml let () = let x =
     Bls12_381.G2.random () in Printf.printf "Compressed: %s\nUncompressed:
     %s\n" Hex.(show (of_bytes (Bls12_381.G2.to_compressed_bytes x))) Hex.(show
     (of_bytes (Bls12_381.G2.to_bytes x))) ``` *)
  let regression_tests () =
    let vectors =
      [
        ( G2.of_bytes_exn
          @@ Hex.to_bytes
               (`Hex
                 "03b7462a980d8d0f71b8adb247bff135340c2732780a31c2961c23ed7532779d72a4f5510754285f6a0f6eac059fed0b0f612738ca78fc16d43a68e53a27a7f43e1f1e2f2720c160af67d2636a799d5a8bf4d8654601543992ad1c0f7293249304c27382c74e088848b3ad156a3ca03f7c4841621710ae09a3c462ad2bf783dcf279ff1836b52837f38be885b59df960109dc5aad7bb0163f11f740e7502377a581d8d02ee209e6e554bffe41b1913b1a6a7f1a72dac9bd63d4448ddc0a3a5af"),
          Hex.to_bytes
            (`Hex
              "83b7462a980d8d0f71b8adb247bff135340c2732780a31c2961c23ed7532779d72a4f5510754285f6a0f6eac059fed0b0f612738ca78fc16d43a68e53a27a7f43e1f1e2f2720c160af67d2636a799d5a8bf4d8654601543992ad1c0f72932493")
        );
        ( G2.of_bytes_exn
          @@ Hex.to_bytes
               (`Hex
                 "17d24507e389a55fa1816bf1ee6b8310b199198d5e43e2e35b1f9e5c546a8e0ac9bd50a6d72a9a27f80023db8db3d6bb08f4787f10c214bc86e8fb9ce079199fc56a4208c3f1e954aef4c3cee810b394ef69ddef9ce965f513995a124fa6286d0341b659d2cf349691758dbf296bc585eb155e73ca21285a293a588556dfadbef2359a3973b49f76b8217f2c49aad91212d2a5ca19f5a95cef69ec782a44767db7dbd0a44fbc2ff2190fc69340aaf59495ad969f6c07288a5ddcfe742681890a"),
          Hex.to_bytes
            (`Hex
              "97d24507e389a55fa1816bf1ee6b8310b199198d5e43e2e35b1f9e5c546a8e0ac9bd50a6d72a9a27f80023db8db3d6bb08f4787f10c214bc86e8fb9ce079199fc56a4208c3f1e954aef4c3cee810b394ef69ddef9ce965f513995a124fa6286d")
        );
        ( G2.of_bytes_exn
          @@ Hex.to_bytes
               (`Hex
                 "12c37d6040d2e2ce9813dd48fdf6abd1754506aa2bfb396c2be7cfabf4375b7ec3d6054d855bc3f93472ac8e8e6ac1280e063837200a2eb0219ecbda76b07b81620f42b524c2d054b1c56e3362a245d8f45cbaf863fc3c01a2cfa20eb4ffe87c151325e3b39c45eef19e7799dcd5edff8ab746ded19983843c9005bd7defd1263d2211ad641f3eb45cf9c6764bcfabca071e2f6b77819c554b6ef9e26a5e23bbb1a83e448afec180f5fcb11d6c740badf015b68a64d80036202791ef19f4e7fb"),
          Hex.to_bytes
            (`Hex
              "b2c37d6040d2e2ce9813dd48fdf6abd1754506aa2bfb396c2be7cfabf4375b7ec3d6054d855bc3f93472ac8e8e6ac1280e063837200a2eb0219ecbda76b07b81620f42b524c2d054b1c56e3362a245d8f45cbaf863fc3c01a2cfa20eb4ffe87c")
        );
      ]
    in
    List.iter
      (fun (p, expected_bytes) ->
        let computed_bytes = G2.to_compressed_bytes p in
        assert (Bytes.equal expected_bytes computed_bytes))
      vectors

  let test_of_compressed_bytes_exn_and_opt_do_not_accept_uncompressed_bytes_representation
      () =
    let x = Bls12_381.G2.random () in
    let x_uncompressed_bytes = Bls12_381.G2.to_bytes x in
    assert (
      Option.is_none (Bls12_381.G2.of_compressed_bytes_opt x_uncompressed_bytes)) ;
    try
      ignore @@ Bls12_381.G2.of_compressed_bytes_exn x_uncompressed_bytes ;
      assert false
    with Bls12_381.G2.Not_on_curve _b -> ()

  let test_of_compressed_bytes_checks_the_point_is_in_the_prime_subgroup () =
    (* These elements have been generated by bls12-381-unix-blst, commit
       ffa2ad5f1c882f05d64c7cb1633c6256b08513bf, by removing the multiplication
       by the cofactor in the random generator. It can be verified the elements
       are not in the prime subgroup by checking multiplying by Fr.order does
       not give zero. *)
    let test_vectors =
      [
        "8a66ad7eb887b5d717d575f884b405d48d0d9226a5d94f61f59ca3851930f427b985202476f94fde3bfd3b4aaecfc16b18570184d399c1bc31c800654b11f678301c9a4921e3d911d8762aee161183de2c200183aba2d5a40b1d86f331760812";
        "92c5cee0b7fa444687c4cb5256bda5f69da2e5a91b8ff27054098dcbef7ca459706f01ebc9e08017b267754daca4aff0134f3e3af64b42e41543a660e9e425843a3cefe79386740b6d7f246991bd059932e3aa2c9dcfb95d2af9308de6e0211a";
        "a751afa4990412de0760043e2e0667112988fd4392a62ae2cdb8815f48303269ffc723a7bf5785cdd96fa6f716836b431795c92dd5216e8c10a65c66f3e393cf4dfc1ab2853ff6476ffb905cd22def12068059cf8d32147fcf3c9d767555c805";
        "a24850a10275c1c1b79fe1c26d974d597e86becb81988f5f53603cd54efb217a34169850d3da10fe54108446d083b1c617ddae040e628fc521e70a8ee00ea73925634594fc437c6f033381cfed8d3a3e0207de9e4935dc6a9fcf29b60c4046ae";
        "b8d0bbcca8aa5a9557e573923fd98cfbba707b2dbf7bd8dca2f8a789b0673cfa5e7d10cc1e8a092a7e53cace647c52ff0c5b73e7e20de48b81b875a82961a3babf2c66e61fcf9c4ea20ba9996825f21519189fd61e17bbb43ba85e396c9c751d";
        "b49ef3a663331f8b3201a238974dc3add41e9d840feda24d6d24b6cc921c53e51d072d535143d4b16b1acefc92812bf5010251dde740eb8cede58681c1ce2921f0d8889822a0d838e1868ca0cd92b29bf7dde15dfd068d5f43752633cf366035";
        "b43b112702d5e7872d6a49bc3b6a584cfd71778d9ec10abc8fb1e15a026e25ecdbb6104f6ba5e1a339acef8c2484c09202a3cb4d94a44e2a00d4a60a731b594a4923d58c0a6f002d303c6e5ebeec5859e5b2aafe3c202bdd50713b8390ecdc24";
      ]
    in
    List.iter
      (fun bytes ->
        let bytes = Hex.to_bytes (`Hex bytes) in
        assert (Option.is_none (Bls12_381.G2.of_compressed_bytes_opt bytes)) ;
        try
          ignore @@ Bls12_381.G2.of_compressed_bytes_exn bytes ;
          assert false
        with Bls12_381.G2.Not_on_curve _b -> ())
      test_vectors

  let get_tests () =
    let open Alcotest in
    let name, common_tests = get_tests () in
    ( name,
      test_case "vectors" `Quick test_vectors
      :: test_case
           "of_compressed_bytes_[opt/exn] verifies the point is in the prime \
            subgroup"
           `Quick
           test_of_compressed_bytes_checks_the_point_is_in_the_prime_subgroup
      :: test_case
           "of_compressed_bytes_opt/exn do not accept uncompressed bytes \
            representation"
           `Quick
           (Utils.repeat
              1000
              test_of_compressed_bytes_exn_and_opt_do_not_accept_uncompressed_bytes_representation)
      :: test_case "Regression tests" `Quick regression_tests
      :: common_tests )
end

module ArithmeticRegressionTests = struct
  (* The test vectors in this module have been generated by the scripts in
     utils, using the implementation bls12-381-unix, commit
     c35cbb3406570ce1465fbf8826cd2595ef02ab8e *)
  let test_vectors () =
    let v =
      [
        ( "002d46747687dde6f0190dfa75b3b9f2c1a838499770a252b11edd4bd5dce471c838357c4019699bbec43b7f36fa6ceb11f17d06979be9465cbec20802d8b3b6c8f7d2634aee63d084e02ac368f4df26ba81108b9beea842fe138fe80f0e4889007212788818dff8343f96f133c2b8dd1f25131a2feff5666a20016ee8f9991a6bfa27dd44483e8138cab37d40fdfc940920ab059b321d262a7df8922e80cd7b305d4f5b8ea3316d33d65d1dedee4b5f375aac5e0ff904b3c063fb1d26437542",
          "0e8a072e3ced0a6fdc15fa15bf31e95025aaaee03ebbf9459fa425728321def36beab54a3fae9e65d69f7def90696d840deec057593c8769822dfb3a8842bbf7cc99f3a42ab678bb8b6d5584bee8ed9fe9a42b6ef0496753a90ec4bed9137ed1002e03114c92b9b0ccef283cbcc94826886b5c71874a828248c4dc185bf6c9315f407a5f44fc584e6141524dc621f1e81287241dd386ffd11788b607c7116c557abe417af68b22cabd9ec0d66425d1c2ccc64266751b236d37ccc839d486ccfc",
          "eb71ea073072246be58b0a7c539741b39cc811792e85ede37c980c8ad52e846c",
          "0c92b4da58b4782af56a5f0af41e6151108d01f02b73491eb481cfee750d9b42897790bae96ee691cfc315e2dbb70040119ad000a51d4606c9433f5b10337bf322446d5efc683af92c7f458a37e0fbad3eca62b791772b69080a2719c9bdc72b031319520182a85bb4c73f71c85ba74dcb4f907e6f5eb0e2c083b94002c04b24b1f1f70160ee9acfa7f45960099d2b3c0acfc9cb2a7b2a22ca567402af0475931bacfe255e9376b3032e85c890234770344f7f7f97d384cfc2f42cd4ebc4d544",
          "002d46747687dde6f0190dfa75b3b9f2c1a838499770a252b11edd4bd5dce471c838357c4019699bbec43b7f36fa6ceb11f17d06979be9465cbec20802d8b3b6c8f7d2634aee63d084e02ac368f4df26ba81108b9beea842fe138fe80f0e4889198eff71b16706a216dc10c50f88f3fa4552386ac3951d58fd10d1320db75d09b2b1d8216d0bc17e81344c82bf01ae1710e066e49e4dc974209daf2414cadf5c3419fc2964e1e152335a758308c2aac4e75153a0a15afb4bf99b04e2d9bc3569",
          "15b39292e23349e8a33cd508bb36758f2f0cc599bb193d6d383a3f473cf25267d639c69153dc2f5f92caba81ad142fe30035550714ab1f2a9ec2c64c6d246f31df1ee9add042091a63f57437c8bfb207ba4547a07969a8dad881e28605b166aa042db7e3b761591116bddf05206648a623a5c28884e6ef636aea3ec049e3fbd18f3355ced2ddaa69077de47ed59f18ca0fff0a0670bc9f307719b3fe84f634b2c80d9f05860d9eea9af4e7c4c74d6ea96056006426a6148ffded51aa7b203689"
        );
        ( "12b3b0fc269694b9a2686dbc7d52b9a4c5dfe67d64a1cfc172a1ea4e973cacaad2be1d76187a97b64852f0eda8b0aadc008ecd0962d0f804f4803b3bf7a3d5e63eee082a8887d54d48c648cd5493301cb6157b31b1d54d4d0f108349f8314ffc0fe243fdba8c18a5bb865367d814d3488c3a9fe0e3b615a4d2f1e75707baec691e534c52f924aa38714fbb8ea043c36008c7807ca9508556866dc2069b469ff21799a99f633462769de80636b5b9d070295200bec8cf96c346e417b6d65a3526",
          "072ca73e751dcf97e4c90fd2e9c8a7e38ed08ab20fa78c61284cee8a466526941f9af97d1e2e1f7ae95fc704d128c8130113b23e1aef05c54ad7f99b924cda91c6d10696e96262630ca7c68dfd4a2d98e4e7c18e33bbaeb983dacac79ff01e970c37400d2cdd6147ba092be6f687114de62506769c7f8d672051cdc6d47211ba6089a78662e44747aaa384f567e3dd90149991456c1c0d35092d6ef06c88f2740cba64c31d87900f562e71f107038a24e80cda455781fb477e35c3bdc0e01e1c",
          "7a52dbdc7dc2f81ebc2d9c82a2ffae17cd35ba5fba27aabd9114981837e0c358",
          "12cfb9403a570237f7bc73a1ee0dfaff72263e64f33bf26878e8eb4e553e965379bbfbfd64232397e9eb3d0758c71f4d0742ca426402bb6cb70e6bb02a48cdd8fff1c019a094052e827dabc5f2f588723692ff1c7522e659bc91d44ed4ad7d9319077b762a949ca9c7918f15ea693467864aa9e592e35fe1a6a1d657ecb0dbfa7e22f93e468c39a391d2e75ade699127027b2bd64c5559b62794441e5db246e564f108852c51223c4a1e8b79e97232167431882befc7296343405161313d5712",
          "12b3b0fc269694b9a2686dbc7d52b9a4c5dfe67d64a1cfc172a1ea4e973cacaad2be1d76187a97b64852f0eda8b0aadc008ecd0962d0f804f4803b3bf7a3d5e63eee082a8887d54d48c648cd5493301cb6157b31b1d54d4d0f108349f8314ffc0a1ecdec7ef3cdf48f95544e6b36d98ed83caba40fcefd1a943eeb49eef609bb0058b3abb82f55c748af44715fbbe74b1139916d902f6143c4ade5afa8050ce54cdda1e59050b048c948cc6a40f725b3f559ff3fe884693c731ae84929a57585",
          "06d3b6d4dcbcbab07cd034c6f108fe5006a53ec43ac2c555391eb42199472dff30ecccc6eb225b5bbfa53cb6a44ccae012815666e40b6f78d6784626066c6257f828c3e0e9381f0e7fe668bf54ea3886045ce77c935f3b573906ef9fc82e5f570fe235afd101c8350d509e221e28c2292a62faf992342004ca090b0c658eeeb47773ba5f9596361ebadf45ea76cdc45d0431cd9e29535a0284d39a2f72f762aa835546ff4fe7f4800d90ab65d51ac40570b8c40fbec3096e2062918377ee364c"
        );
      ]
    in
    List.iter
      (fun (g1, g2, s, g1_plus_g2, minus_g1, s_g1) ->
        let g1 = G2.of_bytes_exn (Hex.to_bytes (`Hex g1)) in
        let g2 = G2.of_bytes_exn (Hex.to_bytes (`Hex g2)) in
        let s = Bls12_381.Fr.of_bytes_exn (Hex.to_bytes (`Hex s)) in
        let g1_plus_g2 = G2.of_bytes_exn (Hex.to_bytes (`Hex g1_plus_g2)) in
        let minus_g1 = G2.of_bytes_exn (Hex.to_bytes (`Hex minus_g1)) in
        let s_g1 = G2.of_bytes_exn (Hex.to_bytes (`Hex s_g1)) in
        assert (G2.(eq g1_plus_g2 (add g1 g2))) ;
        assert (G2.(eq minus_g1 (negate g1))) ;
        assert (G2.(eq s_g1 (mul g1 s))))
      v

  let get_tests () =
    let open Alcotest in
    ( "Regression tests for arithmetic",
      [test_case "Regression tests" `Quick test_vectors] )
end

let () =
  let open Alcotest in
  run
    ~__FILE__
    "G2"
    [
      IsZero.get_tests ();
      ValueGeneration.get_tests ();
      Equality.get_tests ();
      ECProperties.get_tests ();
      Memory.get_tests ();
      BulkOperations.get_tests ();
      UncompressedRepresentation.get_tests ();
      CompressedRepresentation.get_tests ();
      ArithmeticRegressionTests.get_tests ();
      InplaceOperations.get_tests ();
      Constructors.get_tests ();
    ]