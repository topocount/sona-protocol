import { StandardMerkleTree } from "@openzeppelin/merkle-tree"
import * as fs from "fs"

// (1)
let values = [
	// [tokenId								, amount, 			,start, end]
	["0x1", "5000000000000000000", 0, 1],
	["0x2", "2500000000000000000", 0, 1],
	["0x3", "1250000000000000000", 0, 1],
]

// (2)
let tree = StandardMerkleTree.of(values, [
	"uint256",
	"uint256",
	"uint64",
	"uint64",
])

// (3)
console.log("\n\ntree 1")
console.log("Merkle Root:", tree.root)

console.log("leaves: ", Array.from(tree.entries()))
console.log("leaf: ", Array.from(tree.entries())[1])
console.log("leaf: ", tree.leafHash(Array.from(tree.entries())[1][1]))
console.log("proof ", tree.getProof(1))
console.log("tree ", tree.render())
// (4)
//fs.writeFileSync("script/tree.json", JSON.stringify(tree.dump(), null, 2))

console.log("\n\ntree 2")
// (1)
values = [
	// [tokenId								, amount, 			,start, end]
	["0x1", "5000000000000000000", 0, 1],
	["0x2", "2500000000000000000", 0, 1],
	["0x3", "1250000000000000000", 0, 1],
	//["0x1", "10000000000000000000", 1, 2],
	//["0x2", "5000000000000000000", 1, 2],
	//["0x3", "2500000000000000000", 1, 2],
]

// (2)
tree = StandardMerkleTree.of(values, [
	"uint256",
	"uint256",
	"uint256",
	"uint256",
])

// (3)
console.log("Merkle Root:", tree.root)

console.log("leaves: ", Array.from(tree.entries()))
console.log("leaf: ", Array.from(tree.entries())[1])
console.log("leafhash: ", tree.leafHash(Array.from(tree.entries())[1][1]))
console.log("proof ", tree.getProof(1))
console.log("tree ", tree.render())
// (4)
//fs.writeFileSync("script/tree2.json", JSON.stringify(tree.dump(), null, 2))
