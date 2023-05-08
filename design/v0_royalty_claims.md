# Royalty Claims

## Relevant People

- @topocount
- @partyscript

## Overview

One of the primary goals of Sona is to get creators paid more equitably.
Royalty Claims are the v0 way for us to pay creators who mint Tracks,
and patrons who hold the respective Royalty NFT. Royalty amounts are
calculated based by taking some proportion of an available rewards pool
based on plays. This exact calculation is controlled by our backend, but the
focus here is finding a way to make these rewards amounts published and then
transparently claimable on-chain.

The solution proposed within is entirely directed by our on-chain API. [EIP-3668]
is utlized to point clients to query our backend with the needed information.
Once that information is returned from our backend, the royalty-claimant will
be able to submit a payout claim that is provable on-chain.

The upshot of this design is that all distributions and claim history can
be looked up directly from our smart contract and are therefore transparent.
At the same time, this design can scale to serve **millions** of artists and
patrons, with claims unlocked daily.

## Design

Royalty amounts are tracked by an offchain backend, but we want to make that
data accessible not just for claims, but for the purpose of general inquiry.

This is accomplished by providing API access to the backend, and utilizing
[EIP-3668] to curry queries using onchain primitives, such as ERC-721
`tokenId`s and claim intervals, into a query that returns both a
structured payload for submitting a claim but also returning transparent data
from the backend for the sake of presentation to users.

The vehicle for unlocking funds in the Royalty claims contract is a [merkle
tree]. New merkle roots will be published **daily** to make funds available to
Royalty claimants. Claimants can withdraw funds across multiple days by
submitting mulitple claims in a transaction.

The feature that makes this scalable is the utilization of merkle roots
to verify claims onChain. Now, given that we want to minimize gas costs
and make make it as cheap as possible for users to claim their funds, we
want to publish aggregate trees for a given week and a given month. This
gives users the flexibility and incentive to wait and claim their daily
earnings more affordably. We can accomplish this by publishing merkle roots
at weekly and monthly cadences in addition to the daily cadence. While
this would increase the overhead of the protocol, it is relatively insignficant,
since it would increase the admin overhead from 1 tx per day to 3 txs per
day at the worst case, and the cost of each tx in relation to the quantity
of claims is still $O(1)$.

### Root Publishing Flow

A Root will be published with the given struct:

```solidity
struct RoyaltyClaimRoot {
  bytes32 root;
  uint64 start;
  uint64 end;
}
```

tokenIds will have a mapping to the timestamp of their latest claim:

```solidity
mapping(uint256 => uint64) DateTimeLastClaimed
```

Claims can only be processed in monotonically increasing order, so the next
claim `start` time, must match `DateTimeLastClaimed`. This invariant also
prevents duplicate claims against roots of varying timespans.

The backend Service that the `trackRoyalties.sol` contract redirects to
would be responsible for observing the user's claim history and returning
the optimal (read: least expensive/fewest proofs) payload the client can
then pass in. If funds cannot be claimed after 90 days, this would mean that
the maximum quantity of proofs needed to calculate a given quarter is
roughly:

$$
2\ months + 3\ weeks + 6\ days = 11\ proofs
$$

This math is obviously simplified and doesn't account for months ending in
the middle of the week, but those calendaring concerns are implementation
details. This is a roughly 88% reduction in cost compared to an implementation
that only processed daily proofs.

[![root publish flow](https://mermaid.ink/img/pako:eNplkU9LAzEQxb_KEFi2hV0LVXvIoQfx4kGQ6jGX7GZ0w26SNX_UUPrdTTYtFcwhvJlJ3oPfHElvBBJKqurINIDU0lNYJEDtB1RYU6gFt2Pd5O6J6VNVMc20w8-AusdHyT8sV-ULD97ooDq0pZ6MmQG_0EYQPG6-EceNMtoPZZzPA-9H1KLd799skgcT-eQluhtnJgpz6CbphoMxftVFj-52CzYVDQSp_e4OnOf2WiWj9dX6v2Hbrs95FMogZuuXkoJilX2297sEQuAPiiXrSTRwyf7bPyclsyLKTRqi0CouRcK6kGRkAckITTKjZCRRTO8yrdeoe0K9DdiQMAvuL0AJfeeTS10U0hv7XPa0rOv0Cxvgkik?type=png)](https://mermaid.live/edit#pako:eNplkU9LAzEQxb_KEFi2hV0LVXvIoQfx4kGQ6jGX7GZ0w26SNX_UUPrdTTYtFcwhvJlJ3oPfHElvBBJKqurINIDU0lNYJEDtB1RYU6gFt2Pd5O6J6VNVMc20w8-AusdHyT8sV-ULD97ooDq0pZ6MmQG_0EYQPG6-EceNMtoPZZzPA-9H1KLd799skgcT-eQluhtnJgpz6CbphoMxftVFj-52CzYVDQSp_e4OnOf2WiWj9dX6v2Hbrs95FMogZuuXkoJilX2297sEQuAPiiXrSTRwyf7bPyclsyLKTRqi0CouRcK6kGRkAckITTKjZCRRTO8yrdeoe0K9DdiQMAvuL0AJfeeTS10U0hv7XPa0rOv0Cxvgkik)

### Royalty Claim Flow

The claim flow below shows the calls made by a client to the
TrackRoyalties.sol smart contract and the backend API that generates optimal
claim sequences for the requested time period. The end result is the user
receiving the royalty funds in their crypto wallet.

The `end` datetime of the last claim processed is set as the
`DateTimeLastClaimed` for the provided `tokenId` in state.

[![claim flow](https://mermaid.ink/img/pako:eNp1U01P4zAQ_SsjS1UbyXAosAcfQGwRWiTYRQu3pkLTeNpadeysP5CqKv997SSFAruneN545r0Zv-xZZSUxwUajfWkAlFFBQHcEGIcN1TQWMJbotmOe0bY07WhUmtJ4-hPJVHSjcO2w7kswBmtivSQ3xFWwDmZakQmAHn7ePr_8sFoe8n3m5PLy2WG1_W13qIMif-qtFlBpVPW9tdvYTKIyYXrxDYLdkrmTHDJwNgUf0IW3iIws-sZf-yWSnk2Ao1dyAX6tVrMNKjNQoJSOvIfhOwkb5QueGJwy6_kCotOeQ4Va32BADstdIH_-makT_RBT0Gg69aQpr-C9roBPk183SsCawluLW-seySkrJ98Tw1NH35XLXN5Xp6KjefZY25gPwQbUs6wAl5quO5RDo3Hnr4bsYw44OGvDnfQChsXOF-leAlcJ6gY7m84XGdSEr3QMth_0nxT_fbnDEv79dh3nQQY_5hx0cHgHBxUF46wmV6OSybL7knUGLZmAkmWLlqxNN7IHn3amYiK4SJzFJi3uYFMmVqh9Qkmq9C4Pvfu7n6D9C8cODhY?type=png)](https://mermaid.live/edit#pako:eNp1U01P4zAQ_SsjS1UbyXAosAcfQGwRWiTYRQu3pkLTeNpadeysP5CqKv997SSFAruneN545r0Zv-xZZSUxwUajfWkAlFFBQHcEGIcN1TQWMJbotmOe0bY07WhUmtJ4-hPJVHSjcO2w7kswBmtivSQ3xFWwDmZakQmAHn7ePr_8sFoe8n3m5PLy2WG1_W13qIMif-qtFlBpVPW9tdvYTKIyYXrxDYLdkrmTHDJwNgUf0IW3iIws-sZf-yWSnk2Ao1dyAX6tVrMNKjNQoJSOvIfhOwkb5QueGJwy6_kCotOeQ4Va32BADstdIH_-makT_RBT0Gg69aQpr-C9roBPk183SsCawluLW-seySkrJ98Tw1NH35XLXN5Xp6KjefZY25gPwQbUs6wAl5quO5RDo3Hnr4bsYw44OGvDnfQChsXOF-leAlcJ6gY7m84XGdSEr3QMth_0nxT_fbnDEv79dh3nQQY_5hx0cHgHBxUF46wmV6OSybL7knUGLZmAkmWLlqxNN7IHn3amYiK4SJzFJi3uYFMmVqh9Qkmq9C4Pvfu7n6D9C8cODhY)

## Architecture Not Covered Here

This document is intended to convey (and at the same time de-risk) the
communication flows across the stack. Implementation details for the
blockchain layer such as treasury management and value flows on claims are
not covered here. Additionally, the backend implementation details
surrounding claim optimization and onchain state indexing are also not
covered here. These details will be reviewed and refined as the scratch
implementation takes shape.

## Out of Scope

I have not considered what other info the frontend client may need for
informational purposes. The smart contract and backend APIs can be augmented
with these considerations as the UX and design for this flow are fleshed out.

[eip-3668]: https://eips.ethereum.org/EIPS/eip-3668
[merkle tree]: https://github.com/OpenZeppelin/merkle-tree
