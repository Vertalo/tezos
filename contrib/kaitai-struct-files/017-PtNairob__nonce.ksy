meta:
  id: 017-PtNairob__nonce
  endian: be
types:
  fixed_bytes:
    seq:
    - id: size
      type: u4
    - id: value
      size: size
seq:
- id: fixed size (uint30) bytes
  type: fixed_bytes
