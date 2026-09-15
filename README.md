# rain.lib.hash

`LibHashNoAlloc` in `src/LibHashNoAlloc.sol`, published to
[soldeer](https://soldeer.xyz) as `rain-lib-hash`, implements the primitives of
the pattern this document describes for hashing any Solidity value in memory
without allocating.

## Problem

When producing hashes of just about anything that isn't already `bytes` the
common suggestions look something like `keccak256(abi.encode(...))` or
`keccak256(abi.encodePacked(...))`. This appears reasonable as Solidity itself
does not provide an "any type" `keccak256` function but does provide one
(almost) for abi encoding.

When I say "common suggestion" I mean literally the compiler itself gives
outputs like this for any type other than `bytes`.

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

For the purpose of this document we are NOT attempting any specific
compatibility with external systems or standards, etc.

The basic use case is that we are writing contracts that need to convince
themselves that they should authorize some state change.

Often we find ourselves with a lot of state that informs the authorization
verification logic. Too much to store, sign, etc. so first we want to "hash the
data" and just store, compare, sign the hash.

It doesn't really matter in this case what the hashing algorithm is, as long as
it gives us the security guarantees that the contract needs. If the hash is
needed to be known offchain, e.g. so it can be passed back to a future call on
the contract, then the contract can emit the hash into the logs etc.

We are even fine with changing the patterns described in this document over
time. There's no requirement that a hash produced by one contract is compatible
with the hash produced by another. Our goal is that contracts implementing these
patterns can securely accept arbitrary inputs of the types they are written for
(see "Security of composition" below), NOT that the basic approach ossifies due
to unrelated contracts doing different things to each other.

**That is to say, there's no "upgradeable contract" support.**

Further, while we do want to be able to support "any" data type in our pattern,
we do NOT need to support "every" data type in our implementations. It may be
relatively onerous to implement and maintain the required assembly logic to
safely hash some structure, relative to just slapping an abi encoding on the
problem and walking away. The intention is that this work would only be needed
for maybe 1 or 2 structs within a codebase, because there wouldn't be a large
variety of security sensitive hashing to be done for some given
contract/context.

It's also assumed that, because these structs are used on the critical security
path, there would be good reasons to design them for stability and simplicity
already. In this case, the maintainability concerns that always arise when
handling structs in assembly (adding/removing/reordering fields!) are naturally
less of a concern due to their context/usage.

### Encoding and cryptography

An earlier version of the EIP712 spec outlined the difficulty in relying on
encoding formats to provide cryptographic guarantees, under the headings
"Signatures and Hashing overview" and "Transactions and bytestrings" in the
revision that moved the EIP to Final.

https://github.com/ethereum/EIPs/blob/c2e19a6ba0dda0e6fbf846b62e3711d3bc2ebbed/EIPS/eip-712.md

> A good hashing algorithm should satisfy security properties such as
> determinism, second pre-image resistance and collision resistance. The
> keccak256 function satisfies the above criteria when applied to bytestrings.
> If we want to apply it to other sets we first need to map this set to
> bytestrings. It is critically important that this encoding function is
> deterministic and injective. If it is not deterministic then the hash might
> differ from the moment of signing to the moment of verifying, causing the
> signature to incorrectly be rejected. If it is not injective then there are
> two different elements in our input set that hash to the same value, causing a
> signature to be valid for a different unrelated message.
>
> An illustrative example of the above breakage can be found in Ethereum.
> Ethereum has two kinds of messages, transactions 𝕋 and bytestrings 𝔹⁸ⁿ. These
> are signed using eth_sendTransaction and eth_sign respectively. Originally the
> encoding function encode : 𝕋 ∪ 𝔹⁸ⁿ → 𝔹⁸ⁿ was defined as follows:
>
> - encode(t : 𝕋) = RLP_encode(t)
> - encode(b : 𝔹⁸ⁿ) = b
>
> While individually they satisfy the required properties, together they do not.
> If we take b = RLP_encode(t) we have a collision. This is mitigated in
> ethereum/go-ethereum#2940 by modifying the second leg of the encoding
> function:
>
> - encode(b : 𝔹⁸ⁿ) = "\x19Ethereum Signed Message:\n" ‖ len(b) ‖ b where len(b)
>   is the ascii-decimal encoding of the number of bytes in b.
>
> This solves the collision between the legs since RLP_encode(t : 𝕋) never
> starts with \x19. There is still the risk of the new encoding function not
> being deterministic or injective. It is instructive to consider those in
> detail.
>
> As is, the definition above is not deterministic. For a 4-byte string b both
> encodings with len(b) = "4" and len(b) = "004" are valid. This can be solved
> by further requiring that the decimal encoding of the length has no leading
> zeros and len("") = "0".
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
- It is difficult to assess the cryptographic qualities of an encoding scheme
  and high profile mistakes can be found in the wild, including formal standards

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
`3"abc" + 3"def"` with length prefixes and `2"ab" + 4"cdef"`, and then
additional head/tail structures that encode the offsets of the dynamic length
data in an overall prefix to the encoded data.

https://docs.soliditylang.org/en/stable/abi-spec.html#formal-specification-of-the-encoding

Importantly, in light of the discussion in EIP712, the lengths are fixed length
themselves, always represented as a `uint256`. The canonical encoding of one
fixed type tuple is decodable, and that is the whole argument for it: as
`abi.decode` recovers the value, two different values of that type cannot share
an encoding.

So `abi.encode` doesn't have the problems of `abi.encodePacked` nor early geth
implementations. What it does not give is injectivity ACROSS types:
`abi.encode(uint8(1))`, `abi.encode(uint256(1))`, `abi.encode(true)` and
`abi.encode(address(1))` are all the same 32 bytes. That is the same "one hash
domain, one type" restriction the pattern below carries, so the case for the
pattern is cost, not a stronger guarantee.

#### Gas cost of encoding

If `abi.encode` was an efficient function, we could probably be happy that it
has sufficient adoption and time without exploit to use it. Even if there was
some issue, "nobody ever got fired for using `abi.encode`", right?

Doing the same thing as everyone else, and as the security researchers recommend
in audits, is usually a good idea.

The issue here is that `abi.encode` is not particularly gas efficient. This is a
fundamental issue and not at all the "fault" of Solidity. To encode anything
with any algorithm and not cause the original data to be corrupted/unsafe to
use, the EVM must allocate a new region of memory to house the encoded data. If
we allow for dynamic length data types, the UNAVOIDABLE runtime overhead of ANY
schemaless/uncompressed encoding algorithm is:

- Calculate the size of memory to allocate for the encoded output by recursively
  traversing the input data
- Allocate the memory and pay nonlinear gas for expansion costs
- Make a complete copy of the input data
- Write additional data for the encoding itself, e.g. type/length prefixes,
  headers, magic numbers, etc.

The Solidity type system can definitely make a lot of this more efficient,
especially the traversal bit, by generating the traversal process at compile
time but it can't hand wave away the need for allocating and copying.

**Typically, if some algorithm `f(x)` is implemented in a functionally
equivalent way, where one implementation internally encodes `x` and another
avoids it, the no-encode solution saves the encoding's allocate-and-copy cost,
which grows with the size of `x`, less whatever fixed work it does instead (e.g.
extra `keccak256` calls), so the saving ranges from slightly negative for a few
words of `x` to most of the gas for larger inputs.** This saving is of course
most noticeable when the algorithm is relatively efficient, or involves a tight
internal loop over encoding, such that the encoding then starts to dominate the
profile. Even in cases where that is not true, such as comparing the reference
SSTORE2 implementation to
[LibDataContract](https://github.com/rainlanguage/rain.datacontract/blob/252093fbf9edcbe1c0c73c33b16bdefaff53aef1/src/LibDataContract.sol)
we still can see 1k+ gas savings per-write for common usage patterns, with
identical outcomes.

It really just seems to come down to the fact that memory expansion and bulk
copying nested/dynamic is not a cheap thing to do. It's typically not millions
of gas, but it can easily be 1-10k+ gas for what is often unneccessary work.

Note however that `keccak256` itself is non destructive, it can happily produce
a hash on the stack without modifying or allocating any memory at all. Even in
the case that some data is NOT in memory yet and we want to hash it (e.g. on the
stack), there is a dedicated region of memory from `0-0x40` called "scratch
space for hashing methods". We can put any two words in the scratch space and
hash them together without interacting with the allocator at all.

What perhaps is the "fault" of Solidity is that they don't implement `keecak256`
for any type other than `bytes` so we are forced to go all the way to Yul and
write assembly the moment we want to do anything other than `abi.encode`.

## Solution

- Define a pattern to hash any Solidity data structure without allocation and
  minimal memory reads/writes, and is generally efficient
- Convince ourselves the pattern is unambiguous/secure, being both deterministic
  and injective
- Provide a reference implementation of the pattern's primitives, `hashBytes`,
  `hashWords` and `combineHashes` plus the `HASH_NIL` seed, that inline
  implementations can be fuzzed against; composition, i.e. the per-struct steps
  and the fold, is written inline per type from those primitives, and is worked
  as fuzz tests in `test/HashPattern.t.sol` and `test/HashPatternFold.t.sol`
  rather than exported

### The pattern

The memory layout of data in Solidity is very regular across all data types.

https://docs.soliditylang.org/en/stable/internals/layout_in_memory.html

Note that the memory layout is completely different to e.g. the storage layout.
Everything discussed here is specific to data in memory and does not generalise
at all.

Every type ends up in one of 3 buckets:

- 1 or more 32 byte words, of `length` defined by the type
- A 32 byte `length` followed by `length` 32 byte words (most dynamic types)
- A 32 byte `length` followed by `length` bytes (`bytes` and `string` only)

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

Any types that are smaller than 1 word occupy a full word. Unsigned integers,
`address`, `bool` and enums are right-aligned and padded with 0's, so the word
is the same `uint256` equivalent value. Signed integers are right-aligned and
sign-extended, so the word is `uint256(int256(x))`: `int8(-1)` is `0xff…ff`, not
`0x00…ff`. `bytesN` is left-aligned and padded with 0's on the right, so the
word is `uint256(bytes32(x))`: `bytes4(0x01020304)` is `0x01020304` followed by
28 zero bytes, not `0x00…01020304`. The hash is of the word as laid out.

Reference types (arrays of any length including static ones such as
`uint256[1]`, structs of any size including a single field, `bytes` and
`string`) are pointers to that data, from the perspective of the struct. Only
value types are laid out inline. Size does not decide it: a `uint256[1]` member
is exactly one word and is still a pointer word.

This logic is applied recursively.

This means that structs are NOT dynamic length, regardless of how nested or how
many dynamic types appear in their definition, or the definitions of types
within their fields. For example, a `Foo` is ALWAYS 4 words, i.e. 0x80 bytes
long.

Given the above, we can

- Define a pattern for hashing each of the 3 possible memory layouts
- Explain how to handle pointers across non-contigous regions of memory
- Discuss the security of the composition
- Provide a guide for implementation, maintenance and quality assurance

#### Hashing contigious words

In all cases where the size of the data is a known number of words at compile
time we are free to simply hash the known memory region.

For example, a `foo_` as above is hashed by a single `keccak256` reading the
struct's whole 4 words from the pointer. `testHashContiguousWords` in
`test/HashPattern.t.sol` is that assembly, checked against those 4 words read
back independently.

Ignore for now that `c` and `d` are pointers, as that will be discussed later in
this document.

The basic point is that Yul handles what we need for known memory regions very
naturally.

Other than implementation bugs, there's no potential for

- Collisions
- Including data what we did not intend to in the hash input
- Failing to include some part of the struct

Because the size of the data never changes, we can just hardcode it per-type.

#### Hashing dynamic length list of words

Most dynamic length types in Solidity are a list of 32 byte words. This includes
lists of pointers like `Foo[]`, single byte values `bytes1[]`, etc.

The ONLY exceptions to the rule are `bytes` and `string` types.

Again, ignoring pointers for now, we can hash any dynamic length word list with
a single `keccak256` that starts one word past the pointer, skipping the length
prefix, and runs for the length prefix multiplied by a word, converting that
count of words into a count of bytes. `testHashWordList` in
`test/HashPattern.t.sol` is that assembly.

Note that here we DO NOT include the length prefix in the bytes that we hash.

This gives us the same behaviour as the case of hashing static length data, but
with lengths known only at runtime.

When it comes to composition we do not want to rely on length prefixes for
safety guarantees, as they are not always available. As EIP712 explained, length
prefixes can introduce ambiguity as easily as they can resolve them as in the
case of packed encoding. Ideally we can show security without the need for any
additional metadata about our words.

#### Hashing dynamic length byte strings

The two byte length types `bytes` and `string` are the only types in Solidity
that may not have whole-word lengths. We MUST respect the true length of `bytes`
and `string` in bytes, otherwise we introduce ambiguity.

If we rounded the length up to whole words instead then `hex"01"` and
`hex"0100"` would hash the same word, `0x01` followed by 31 zero bytes, when
nothing has been written past them, even though the first is 1 byte and the
second is 2 bytes in _length_. Hashing exactly `length` bytes reads nothing past
the end of the data, so the pattern never depends on what the allocator does
beyond it, including where it leaves the free memory pointer.

The assembly for this is actually simpler than dealing with words as we do not
need to convert between length/bytes: skip the length prefix as above, then take
the length prefix as the count of bytes it already is. It is the same for
`string` and `bytes`. `testHashBytesExampleIsKeccakOfBytes` and
`testHashStringExampleIsKeccakOfBytes` in `test/HashPattern.t.sol` are that
assembly over each type, and `testBytesTrueLength` is the `hex"01"` /
`hex"0100"` pair above.

Note that pointers never appear in `bytes` nor `string`, or if they do, they are
not going to be dereferenced by our hashing logic. That single `keccak256` is
all that is needed to hash `bytes` and `string` types.

#### Handling pointers

It would be pointless to hash pointers (no pun intended). A pointer is merely an
offset in memory, which has very little to do with the data on the other side of
it, and is not even deterministic.

We find pointers in Solidity wherever a reference type (array, struct, `bytes`,
`string`) is an item or field in another struct or list, whatever its size.

Solidity does not allow mixed type lists so all pointers are at least found in
predictable positions. We always know at compile time whether something is a
pointer or not, either because it's a field at a known offset, or we are dealing
with an individual or list or pointers directly.

To reliably handle pointers without allocations:

- Compute the hash of all data up to the pointer
- Compute the hash of all data referenced by the pointer
- Hash these two hashes together

Using our `Foo` struct from above as an example this would look like:

- Hash the first two words as a contigious memory region of known size as `A`
- Hash the dynamic word list `foo_.c` as `B`
- Write `A` and `B` to scratch space at `0` and `0x20` respectively
- Hash the scratch space to produce `C`
- Hash the bytes `foo_.d` as `D`
- Write `C` and `D` to scratch space as above
- Hash the scratch space to produce `E`, which is our final hash of `Foo`

`testStructWithPointersHashesAsNestedNodes` in `test/HashPattern.t.sol` is those
steps as assembly, checked against A to E rebuilt with `abi.encode`.

If we had a list of pointers, such as a `Foo[]` then this would be modelled as a
simple fold/reduce-style accumulator, seeded with the nil hash (see below),
where each item is hashed as above individually then hashed into the
accumulator. I.e. Start from the nil hash N, hash `foos_[0]` to hash A, then
write N and A to scratch and hash to produce B, then hash `foos_[1]` to hash C,
and hash B and C to produce D, etc.

How much cheaper this process of iterating and accumulating a hash is than
`keccak256(abi.encode(foos_))` depends almost entirely on how much data sits
behind each pointer. The fold pays a near-fixed cost per `keccak256` call (five
per `Foo` above plus one to fold it into the accumulator) and only 6 gas per
word hashed, whereas `abi.encode` copies every word of every element and writes
the head/tail offsets and lengths before hashing once. Measured with Foundry
under this repo's compiler settings: with `c` and `d` empty the fold costs about
the same or slightly more than encoding; with a handful of words in each it
costs roughly a third to nearly half less; with a kilobyte or so per element it
costs about a fifth, and the fraction keeps falling as the data grows.

##### Nil hash prefix

If we are handling a pointer and have no hash, e.g. we're directly hashing an
array of pointers, we start with the hash of nil bytes, i.e. `keccak256(0, 0)`.

If the array is 0 length then the hash will be the nil hash, regardless of the
type behind the pointers.

The seed is also what separates a one-item array from its item: `[x]` hashes to
`hash(nil + hash(x))` rather than `hash(x)`.

#### Reference implementation

`LibHashNoAlloc` in `src/LibHashNoAlloc.sol` carries the primitives of the
pattern and nothing above them: the three leaf hashers, the binary node, and the
seed that a fold starts from.

```solidity
bytes32 constant HASH_NIL =
    0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

library LibHashNoAlloc {
    function hashBytes(bytes memory data) internal pure returns (bytes32);
    function hashWords(bytes32[] memory words) internal pure returns (bytes32);
    function hashWords(uint256[] memory words) internal pure returns (bytes32);
    function combineHashes(bytes32 a, bytes32 b) internal pure returns (bytes32);
}
```

`hashWords` is overloaded on `bytes32[]` and `uint256[]`, which hash the same
words to the same hash. `HASH_NIL` is a file level constant, not a member of the
library, and is imported alongside it.

Composition is not exported. The steps for a struct and the fold over a list of
pointers are written inline per type from these four, as "Handling pointers"
above sets out. All four hash raw bytes with no type, length or domain tag, so
their outputs coincide across types wherever the hashed bytes do; the NatSpec on
each function lists what collides with what, and "Across types nothing is
unambiguous" below is why that matters.

Install with [soldeer](https://soldeer.xyz):

```sh
forge soldeer install rain-lib-hash~<version>
```

and import the library and the seed together:

```solidity
import {LibHashNoAlloc, HASH_NIL} from
    "rain-lib-hash-<version>/src/LibHashNoAlloc.sol";
```

#### Security of composition

Assume that we're comfortable with concepts like blockchains and merkle trees,
that rely on hashes of hashes to iteratively build a single hash out of a system
of hashes.

We need to convince ourselves that the hashing process above is unambiguous, and
to be precise about what "unambiguous" covers. The pattern hashes raw memory
with no type, length or domain tag, so it is injective only under a restriction
that the caller has to uphold.

##### The restriction: one hash domain, one type

Every position in a composition is fixed at compile time: a struct field is
always the same type, a list always holds the same type, and a pointer is always
followed to a value of the same type. A hash is only ever compared with, stored
alongside, or signed in the same domain as, hashes of values of the same type.
Under that restriction injectivity follows by induction over the type, and each
step relies on nothing but the collision resistance of `keccak256`:

- Contiguous words of a size known at compile time: the hashed bytes are the
  value, so equal hashes mean equal values.
- A dynamic list of `n` words: the hashed bytes are the `32n` bytes of the
  words. Lists of different lengths hash inputs of different lengths, and lists
  of the same length hash inputs that differ wherever the lists do. The `32n`
  byte input already commits to `n`, which is why the length prefix is not
  hashed.
- `bytes` and `string`: the hashed bytes are the value, at its true length.
- A pointer: `hash(hash(a) + hash(b))` equals `hash(hash(c) + hash(d))` only if
  `hash(a)` = `hash(c)` and `hash(b)` = `hash(d)`, and as `a`, `c` share a type
  and `b`, `d` share a type, by induction `a` = `c` and `b` = `d`.
- A list of pointers folded from the nil hash: the fold over 0 items is the hash
  of 0 bytes and the fold over `n` >= 1 items is
  `hash(fold(n - 1) + hash(item))`, a hash of 64 bytes. If the folds over `n`
  and `m` items are equal, with `n` <= `m`, peeling one layer at a time gives
  `fold(n - 1)` = `fold(m - 1)` and equal last-item hashes, down to `fold(0)` =
  `fold(m - n)`; the hash of 0 bytes cannot equal a hash of 64 bytes, so `n` =
  `m`, and each peeled pair of equal item hashes is, by induction over the item
  type, a pair of equal items.

As `keccak256` always produces hashes exactly 32 bytes long for all inputs, a
node is always exactly two hashes and needs no length prefix, so we avoid the
issues seen with both including and excluding length prefixes, such as those
seen in `abi.encodePacked`.

##### Across types nothing is unambiguous

Any two values of DIFFERENT types whose hashed bytes coincide hash identically.
Concretely, with the reference implementation:

- `hashBytes` over `32n` bytes equals `hashWords` over those `n` words, for
  `bytes32[]` and `uint256[]` alike, and equals a static `bytes32[n]` hashed as
  contiguous words.
- `hashBytes` over the 64 bytes `hash(c) + hash(d)` equals
  `combineHashes(hash(c), hash(d))`. A `bytes` LEAF whose content is two hashes
  is indistinguishable from the NODE built from those hashes. In merkle tree
  terms this is the leaf/node second preimage that RFC 6962 rules out by
  prefixing leaves with `0x00` and nodes with `0x01`; this pattern has no such
  prefix.
- `hashBytes` over empty bytes, `hashWords` over an empty list and the fold over
  an empty list of pointers of any type are all the nil hash.
- A struct whose fields are all pointers has no data before its first pointer,
  so "Handling pointers" starts it from the nil hash and builds the same tree
  the fold builds: `struct { bytes d1; bytes d2; }` hashes as the `bytes[]`
  `[d1, d2]` for every value, and in general an `n`-field struct of `T` pointer
  fields hashes as an `n`-item `T[]`. Unlike the others this is a whole-type
  collision: it holds for every value of both types, not just where their hashed
  bytes happen to coincide.

None of these is a collision within a type, so none of them touches the
induction above. They bite the moment the restriction is dropped: if one hash
domain (one storage mapping, one signed message format, one set of preimages a
contract accepts) admits values of more than one type, then whoever controls a
`bytes` leaf can present the node of a different structure, and an empty list of
one type passes as an empty list of another. A contract that must accept more
than one type in the same domain has to add its own domain separation, e.g. hash
a per-type constant into the composition the way EIP712 hashes a type hash into
every struct hash. The reference implementation adds none.

Whatever this induction is worth as a formal proof, the same is available for
`abi.encode`: decodability gives it injectivity per type, and neither argument
reaches past one type. The pattern gets there without producing the encoding,
which is where the saving is.

#### Implementing and testing the pattern

An inline implementation states each hashed type's shape twice: once as the type
definition, and once as the size literal its assembly hashes, such as the `0x80`
for the 4 word `Foo` above. Nothing in the compiler ties the two together, so
adding, removing or reordering a field and leaving the literal alone hashes a
different set of words than the definition describes, with no error and no
revert. A struct that gained a field is then signed and stored under a hash
covering one field fewer than whoever signed it believes.

Two fuzz tests per hashed type keep the literal and the definition equal. Both
take their expected value from Solidity builtins that never see the literal, so
neither can pass by repeating the same mistake:

- The hash test asserts the inline hash equals a hash built without the literal:
  `keccak256(abi.encode(<every field>))` where the fields are values, and the
  same composition of `keccak256` over each dereferenced field where they are
  pointers. A field the literal misses is a field `abi.encode` still encodes, so
  the two disagree.
- The allocation test asserts the free memory pointer moves by exactly the size
  literal across a construction of the type. A field added to the definition
  moves the pointer further than the literal.

`test/HashPattern.t.sol` and `test/HashPatternFold.t.sol` are the hash tests for
the `Foo` used throughout this document, over the struct and over a list of
them, and `test/MemoryLayout.t.sol` is the allocation test for its `0x80`. Copy
their shape per type rather than reusing them: they are written against `Foo`,
and the point of the check is that it is derived from the type it covers.

## Dev stuff

### Local environment & CI

Uses nixos.

Install `nix` - https://nixos.org/download.html.

Run `nix develop` in this repo to drop into the shell. Please ONLY use the nix
version of `foundry` for development, to ensure versions are all compatible.

The commands CI runs live in the shared `rainix-sol` workflow at
https://github.com/rainlanguage/rainix, which
`.github/workflows/rainix-sol.yaml` calls; `flake.nix` only re-exports the
rainix packages and dev shells.

## Legal stuff

Everything is under DecentraLicense 1.0 (DCL-1.0) which can be found in
`LICENSES/`.

This is basically `CAL-1.0` which is an open source license
https://opensource.org/license/cal-1-0

The non-legal summary of DCL-1.0 is that the source is open, as expected, but
also user data in the systems that this code runs on must also be made available
to those users as relevant, and that private keys remain private.

Roughly it's "not your keys, not your coins" aware, as close as we could get in
legalese.

This is the default situation on permissionless blockchains, so shouldn't
require any additional effort by dev-users to adhere to the license terms.

This repo is REUSE 3.2 compliant https://reuse.software/spec-3.2/ and compatible
with `reuse` tooling (also available in the nix shell here).

```
nix develop -c reuse lint
```

## Contributions

Contributions are welcome **under the same license** as above.

Contributors agree and warrant that their contributions are compliant.
