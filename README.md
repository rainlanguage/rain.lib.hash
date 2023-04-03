# rain.lib.hash

Docs at https://rainprotocol.github.io/rain.lib.hash

## Problem

When producing hashes of just about anything that isn't already `bytes` the
common suggestions look something like `keccak256(abi.encode(...))` or
`keccak256(abi.encodePacked(...))`. This appears reasonable as Solidity itself
does not provide an "any type" `keccak256` function but does provide one (almost)
for abi encoding.

When I say "common suggestion" I mean literally the compiler itself gives outputs
like this for any type other than `bytes`.

```
➜ keccak256(address(0))
Compiler errors:
error[7556]: TypeError: Invalid type for argument in function call. Invalid implicit conversion from address to bytes memory requested. This function requires a single bytes argument. Use abi.encodePacked(...) to obtain the pre-0.5.0 behaviour or abi.encode(...) to use ABI encoding.
  --> ReplContract.sol:14:19:
   |
14 |         keccak256(address(0));
```

This approach raises two questions for me:

- Why are we relying on interface encodings to satisfy cryptographic properties?
- Encoding requires complex recursive/nested data processing, memory expansion,
  and making more than a full copy of the data to include headers, is that
  significant gas cost strictly necessary?

### Non goals

For the purpose of this document we are NOT attempting any specific compatibility
with external systems or standards, etc.

The basic use case is that we are writing contracts that need to convince
themselves that they should authorize some state change.

Often we find ourselves with a lot of state that informs the authorization
verification logic. Too much to store, sign, etc. so first we want to
"hash the data" and just store, compare, sign the hash.

It doesn't really matter in this case what the hashing algorithm is, as long as
it gives us the security guarantees that the contract needs. If the hash is
needed to be known offchain, e.g. so it can be passed back to a future call on
the contract, then the contract can emit the hash into the logs etc.

We are even fine with changing the patterns described in this document over time.
There's no requirement that a hash produced by one contract is compatible with
the hash produced by another. Our goal is that contracts implementing these
patterns can securely accept arbitrary inputs, NOT that the basic approach
ossifies due to unrelated contracts doing different things to each other.

**That is to say, there's no "upgradeable contract" support.**

Further, while we do want to be able to support "any" data type in our pattern,
we do NOT need to support "every" data type in our implementations. It may be
relatively onerous to implement and maintain the required assembly logic to
safely hash some structure, relative to just slapping an abi encoding on the
problem and walking away. The intention is that this work would only be needed
for maybe 1 or 2 structs within a codebase, because there wouldn't be a large
variety of security sensitive hashing to be done for some given contract/context.

It's also assumed that, because these structs are used on the critical security
path, there would be good reasons to design them for stability and simplicity
already. In this case, the maintainability concerns that always arise when
handling structs in assembly (adding/removing/reordering fields!) are naturally
less of a concern due to their context/usage.

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

**Typically, my experience has shown that if some algorithm `f(x)` is implemented
in a functionally equivalent way, where one implementation internally encodes `x`
and another avoids it, the no-encode solution often costs 40-80%+ less gas.**
This saving is of course most noticeable when the algorithm is relatively
efficient, or involves a tight internal loop over encoding, such that the
encoding then starts to dominate the profile. Even in cases where that is not
true, such as comparing the reference SSTORE2 implementation to
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

## Solution

- Define a pattern to hash any Solidity data structure without allocation and
  minimal memory reads/writes, and is generally efficient
- Convince ourselves the pattern is unambiguous/secure, being both deterministic
  and injective
- Provide a reference implementation of the pattern that can be fuzzed against
  to show inline implementations of the pattern provide valid outputs

### The pattern

The memory layout of data in Solidity is very regular across all data types.

https://docs.soliditylang.org/en/v0.8.19/internals/layout_in_memory.html

It is optimised so that the allocator always has the free memory pointer at a
multiple of 32.

Note that the memory layout is completely different to e.g. the storage layout.
Everything discussed here is specific to data in memory and does not generalise
at all.

All non-struct types end up in one of 3 buckets:

- 1 or more 32 byte words, of `length` defined by the type
- A 32 byte `length` followed by `length` 32 byte words (most dynamic types)
- A 32 byte `length` followed by `length` bytes (`bytes` and `string` only)

Note that in the last case, the allocator will still move the free memory pointer
to a multiple of 32 bytes even if that points past the end of the data structure.

The variables and structs that reference these things are pointers to them, or
even nested pointers in the case of structs. The pointers can be either on the
stack or in memory, depending on context.

Consider the struct

```solidity
struct Foo {
    uint256 a;
    address b;
    uint256[] c;
    bytes d;
}
```

If we had some `foo_` such that `Foo memory foo_ = Foo(...);` then `foo_` will
be a pointer, either on the stack or in memory, depending on compiler
optimisations.

The thing it points to falls into the first bucket, a 4-word region of memory
defined by its type. This may not be intuitive but all of `uint256`, `address`,
`uint256[]` and `bytes`, and all other types, are all a full singular word in
the struct.

Any types that are smaller than 1 word are padded with 0's such that they retain
the same `uint256` equivalent value.

Any types that are larger, or potentially larger than 1 word are pointers to that
data, from the perspective of the struct.

This logic is applied recursively.

This means that structs are NOT dynamic length, regardless of how nested or how
many dynamic types appear in their definition, or the definitions of types within
their fields. For example, a `Foo` is ALWAYS 4 words, i.e. 0x80 bytes long.

Given the above, we can

- Define a pattern for hashing each of the 3 possible memory layouts
- Explain how to handle pointers across non-contigous regions of memory
- Discuss the security of the composition
- Provide a guide for implementation, maintenance and quality assurance

#### Hashing contigious words

In all cases where the size of the data is a known number of words at compile
time we are free to simply hash the known memory region.

For example, we could hash a `foo_` as above like so

```solidity
assembly ("memory-safe") {
    let hash_ := keccak256(foo_, add(foo_, 0x80))
}
```

Ignore for now that `c` and `d` are pointers, as that will be discussed later in
this document.

The basic point is that the code example shows that Yul handles what we need
for known memory regions very naturally.

Other than implementation bugs, there's no potential for

- Collisions
- Including data what we did not intend to in the hash input
- Failing to include some part of the struct

Because the size of the data never changes, we can just hardcode it per-type.

#### Hashing dynamic length list of words

Most dynamic length types in Solidity are a list of 32 byte words. This includes
lists of pointers like `Foo[]`, single byte values `bytes1[]`, etc.

The ONLY exceptions to the rule are `bytes` and `string` types.

Again, ignoring pointers for now, we can hash any dynamic length word list as

```solidity
assembly ("memory-safe") {
    // Assume bar_ is some dynamic length list of words
    let hash_ := keccak256(
        // Skip the length prefix
        add(bar_, 0x20),
        // Read the length prefix and multiply by 0x20 to know how many _words_
        // to hash
        mul(mload(bar_), 0x20)
    )
}

Note that here we DO NOT include the length prefix in the bytes that we hash.

This gives us the same behaviour as the case of hashing static length data, but
with lengths known only at runtime.

When it comes to composition we do not want to rely on length prefixes for safety
guarantees, as they are not always available. As EIP712 explained, length
prefixes can introduce ambiguity as easily as they can resolve them as in the
case of packed encoding. Ideally we can show security without the need for any
additional metadata about our words.

#### Hashing dynamic length byte strings

The two byte length types `bytes` and `string` are the only types in Solidity
that may not have whole-world lengths. Even though the allocator retains a
multiple of 0x20 on the free memory pointer, we MUST respect the true length of
`bytes` and `string` in bytes, otherwise we introduce ambiguity.

If we did not respect the length then `hex"01"` and `hex"0100"` would hash to
the same value, as they both have 0x20 bytes _allocated_ to them in memory, even
though the first is 1 byte and the second is 2 bytes in _length_.

The assembly for this is actually simpler than dealing with words as we do not
need to convert between length/bytes. It is the same for `string` and `bytes`.

```solidity
assembly ("memory-safe") {
    // Assume baz_ is some bytes/string
    let hash_ := keccak256(
        // Skip the length prefix
        add(baz_, 0x20),
        // Read the length prefix to know how many _bytes_ to hash
        mload(baz_)
    )
}

Note that pointers never appear in `bytes` nor `string`, or if they do, they are
not going to be dereferenced by our hashing logic. This assembly above is all
that is needed to hash `bytes` and `string` types.