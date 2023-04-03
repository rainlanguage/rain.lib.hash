# rain.lib.hash

Docs at https://rainprotocol.github.io/rain.lib.hash

## Problem

When producing hashes of just about anything that isn't already `bytes` the
common suggestions look something like `keccak256(abi.encode(...))` or
`keccak256(abi.encodePacked(...))`. This appears reasonable as Solidity itself
does not provide an "any type" `keccak256` function but does provide one (almost)
for abi encoding.

This approach raises two questions for me:

- Why are we relying on interface encodings to satisfy cryptographic properties?
- Encoding requires complex recursive/nested data processing, memory expansion,
  and making more than a full copy of the data to include headers, is that
  significant gas cost strictly necessary?

### Encoding and cryptography

An earlier version of the EIP712 spec outlined the difficulty in relying on
encoding formats to provide cryptographic guarantees.

> A good hashing algorithm should satisfy security properties such as
> determinism, second pre-image resistance and collision resistance. The
> keccak256 function satisfies the above criteria when applied to bytestrings. If
> we want to apply it to other sets we first need to map this set to bytestrings.
> It is critically important that this encoding function is deterministic and
> injective. If it is not deterministic then the hash might differ from the
> moment of signing to the moment of verifying, causing the signature to
> incorrectly be rejected. If it is not injective then there are two different
> elements in our input set that hash to the same value, causing a signature to
> be valid for a different unrelated message.
>
> An illustrative example of the above breakage can be found in Ethereum.
> Ethereum has two kinds of messages, transactions 𝕋 and bytestrings 𝔹⁸ⁿ. These
> are signed using eth_sendTransaction and eth_sign respectively. Originally the
> encoding function encode : 𝕋 ∪ 𝔹⁸ⁿ → 𝔹⁸ⁿ was defined as follows:
>
> - encode(t : 𝕋) = RLP_encode(t)
> - encode(b : 𝔹⁸ⁿ) = b
>
> encode(b : 𝔹⁸ⁿ) = "\x19Ethereum Signed Message:\n" ‖ len(b) ‖ b where len(b) is
> the ascii-decimal encoding of the number of bytes in b.
>
> This solves the collision between the legs since RLP_encode(t : 𝕋) never starts
> with \x19. There is still the risk of the new encoding function not being
> deterministic or injective. It is instructive to consider those in detail.
>
> As is, the definition above is not deterministic. For a 4-byte string b both
> encodings with len(b) = "4" and len(b) = "004" are valid. This can be solved by
> further requiring that the decimal encoding of the length has no leading zeros
> and len("") = "0".
>
> The above definition is not obviously collision free. Does a bytestring
> starting with "\x19Ethereum Signed Message:\n42a…" mean a 42-byte string
> starting with a or a 4-byte string starting with 2a?. This was pointed out in
> Geth issue #14794 and motivated Trezor to not implement the standard as-is.
> Fortunately this does not lead to actual collisions as the total length of the
> encoded bytestring provides sufficient information to disambiguate the cases.
>
> Both determinism and injectiveness would be trivially true if len(b) was left
> out entirely. The point is, it is difficult to map arbitrary sets to
> bytestrings without introducing security issues in the encoding function. Yet
> the current design of eth_sign still takes a bytestring as input and expects
> implementors to come up with an encoding.

This is good context that has sadly been removed from current versions of the
EIP.

The key takeaways are:

- We need something determinstic and injective, which can probably be summarised
  in a single word as "unambiguous"
- Hashing bytes is secure by default and any encoding scheme's security can only
  be less than or equal to the security of the hash of the raw data before it is
  encoded
- It is difficult to assess the cryptographic qualities of an encoding scheme and
  high profile mistakes can be found in the wild, including formal standards

#### Collisions with ABI encoding

Perhaps unsurprisingly we can find one of these issues in `abi.encodePacked` as
this encoding scheme simply concatenates bytes together.

This means that `"abc" + "def"` and `"ab" + "cdef"` will pack to the same final
bytestring, `"abcdef"`.

We can suggest potential workarounds like "only use packed encoding for fixed
length input data", but it's clear that packed encoding is situationally useful
at best, and dangerous at worst.

The suggested fix is usually to use `abi.encode`, which adds additional
information to the raw data as part of the encoding. Something like
`3"abc" + 3"def"` with length prefixes and `2"ab" + 4"cdef"`, and then additional
head/tail structures that encode the offsets of the dynamic length data in an
overall prefix to the encoded data.

https://docs.soliditylang.org/en/develop/abi-spec.html#formal-specification-of-the-encoding

Importantly, in light of the discussion in EIP712, the lengths are fixed length
themselves, always represented as a `uint256`, so the full `abi.encode` encoding
of the underlying data is probably safe.

So `abi.encode` doesn't have the problems of `abi.encodePacked` nor early geth
implementations, but is that a strong proof that it doesn't introduce new
problems?

#### Gas cost of encoding

If `abi.encode` was an efficient function, we could probably be happy that it has
sufficient adoption and time without exploit to use it. Even if there was some
issue, "nobody ever got fired for using `abi.encode`", right?

Doing the same thing as everyone else, and as the security researchers recommend
in audits, is usually a good idea.

The issue here is that `abi.encode` is not particularly gas efficient. This is a
fundamental issue and not at all the "fault" of Solidity. To encode anything with
any algorithm and not cause the original data to be corrupted/unsafe to use, the
EVM must allocate a new region of memory to house the encoded data. If we allow
for dynamic length data types, the UNAVOIDABLE runtime overhead of ANY
schemaless/uncompressed encoding algorithm is:

- Calculate the size of memory to allocate for the encoded output by recursively
  traversing the input data
- Allocate the memory and pay nonlinear gas for expansion costs
- Make a complete copy of the input data
- Write additional data for the encoding itself, e.g. type/length prefixes,
  headers, magic numbers, etc.

The Solidity type system can definitely make a lot of this more efficient,
especially the traversal bit, by generating the traversal process at compile time
but it can't hand wave away the need for allocating and copying.

Typically, my experience has shown that if some algorithm `f(x)` is implemented
in a functionally equivalent way, where one implementation internally encodes `x`
and another avoids it, the no-encode solution often costs 40-80%+ less gas. This
saving is of course most noticeable when the algorithm is relatively efficient,
or involves a tight internal loop over encoding, such that the encoding then
starts to dominate the profile. Even in cases where that is not true, such as
comparing the reference SSTORE2 implementation to
[LibDataContract](https://github.com/rainprotocol/sol.lib.datacontract/blob/main/src/LibDataContract.sol) we still can see 1k+ gas savings per-write for common usage patterns, with
identical outcomes.

It really just seems to come down to the fact that memory expansion and bulk
copying nested/dynamic is not a cheap thing to do. It's typically not millions of
gas, but it can easily be 1-10k+ gas for what is often unneccessary work.

Note however that `keccak256` itself is non destructive, it can happily produce
a hash on the stack without modifying or allocating any memory at all. Even in
the case that some data is NOT in memory yet and we want to hash it
(e.g. on the stack), there is a dedicated region of memory from `0-0x40` called
"scratch space for hashing methods". We can put any two words in the scratch
space and hash them together without interacting with the allocator at all.

What perhaps is the "fault" of Solidity is that they don't implement `keecak256`
for any type other than `bytes` so we are forced to go all the way to Yul and
write assembly the moment we want to do anything other than `abi.encode`.



Consider that `hash(hash("abc") + hash("def"))` won't collide with
`hash(hash("ab") + hash("cdef"))`. It should be easier to convince ourselves
this is true for all possible pairs of byte strings than it is to convince
ourselves that the ABI serialization is never ambigious. Inductively we can
scale this to all possible data structures that are ordered compositions of
byte strings. Even better, the native behaviour of `keccak256` in the EVM
requires no additional allocation of memory. Worst case scenario is that we
want to hash several hashes together like `hash(hash0, hash1, ...)`, in which
case we can write the words after the free memory pointer, hash them, but
leave the pointer. This way we pay for memory expansion but can re-use that
region of memory for subsequent logic, which may effectively make the
expansion free as we would have needed to pay for it anyway. Given that hash
checks often occur early in real world logic due to
checks-effects-interactions, this is not an unreasonable assumption to call
this kind of expansion "no alloc".

One problem is that the gas saving for trivial abi encoding,
e.g. ~1-3 uint256 values, can be lost by the overhead of jumps and stack
manipulation due to function calls.

```
struct Foo {
  uint256 a;
  address b;
  uint32 c;
}
```

The simplest way to hash `Foo` is to just hash it (crazy, i know!).

```
assembly ("memory-safe") {
  hash_ := keccak256(foo_, 0x60)
}
```

Every struct field is 0x20 bytes in memory so 3 fields = 0x60 bytes to hash
always, with the exception of dynamic types. This costs about 70 gas vs.
about 350 gas for an abi encoding based approach.
library LibHashNoAlloc {
    function hash(bytes memory data_) internal pure returns (bytes32 hash_) {
        assembly ("memory-safe") {
            hash_ := keccak256(add(data_, 0x20), mload(data_))
        }
    }

    function hash(uint256[] memory array_) internal pure returns (bytes32 hash_) {
        assembly ("memory-safe") {
            hash_ := keccak256(add(array_, 0x20), mul(mload(array_), 0x20))
        }
    }
}