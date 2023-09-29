import type { Address } from "viem"
import sepoliaDeployments from "../deploys/11155111.json"
import testDeployments from "../deploys/31337.json"
interface ContractDeployments {
	[key: string]: `0x${string}`
}

interface Deployments {
	[key: string]: ContractDeployments
}

interface DeploymentsOutput {
	[key: string]: `0x${string}`
}

interface DeploymentsOutputFile {
	[key: string]: DeploymentsOutput
}

// TODO parse these files with zod to get the types
function curryDeploymentsOutputFiles(
	files: DeploymentsOutputFile[],
): Deployments {
	return files.reduce((acc, file) => {
		const chainId = Object.keys(file).pop()
		if (!chainId) throw new Error("No chainId found in deployments file")
		const deployments = file[chainId]
		for (const [contractName, address] of Object.entries(deployments)) {
			if (!acc[contractName]) {
				acc[contractName] = {}
			}
			acc[contractName][chainId] = address as Address
		}

		return acc
	}, {})
}

const result = curryDeploymentsOutputFiles([
	sepoliaDeployments as DeploymentsOutputFile,
	// testDeployments,
])

export default result
