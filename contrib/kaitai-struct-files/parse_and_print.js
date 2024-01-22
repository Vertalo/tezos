// For the script inspiration see: https://doc.kaitai.io/lang_javascript.html
//
// This script is meant to be used inside `kaitai_e2e.sh`.
//
// This script does the following:
//   1. Loads autogenerated Javascript parser(`parser_path`).
//   2. Parse binary encoded data (`input_path`) using parser from 1.
//   3. Print parsed data to console.
//
// Motivation: Provided that parser from 1. is able to parse (and later print)
// valid input from 2. we increase out trust in the semantic correctness of
// the autogenerated parser.
//

const parser_path = process.argv[2]
const input_path = process.argv[3]
const valid = process.argv[4]

const fs = require("fs");
const OctezData = require(parser_path);
const KaitaiStream = require('kaitai-struct/KaitaiStream');

const fileContent = fs.readFileSync(input_path);

const stream = new KaitaiStream(fileContent);
if(valid == "false") {
  try {
    new OctezData(stream);
    process.exit(1);
  } catch (e) {
    console.log(e.message);
    process.exit(0);
  }
} else {
  const data = new OctezData(stream);
  delete data._io;
  delete data._parent;
  delete data._root;
  console.log(data);
  process.exit(0);
}
