const solc = require('solc');
const fs = require('fs');
const path = require('path');

// Create artifacts directory structure
const artifactsDir = path.join(__dirname, 'artifacts');
const contractsDir = path.join(artifactsDir, 'contracts');
const kindoraSolDir = path.join(contractsDir, 'Kindora.sol');
const mocksDir = path.join(contractsDir, 'mocks');
const mocksSolDir = path.join(mocksDir, 'MockUniswapV2.sol');

[artifactsDir, contractsDir, kindoraSolDir, mocksDir, mocksSolDir].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

// Read contract files
const kindoraSource = fs.readFileSync(path.join(__dirname, 'contracts/Kindora.sol'), 'utf8');
const mocksSource = fs.readFileSync(path.join(__dirname, 'contracts/mocks/MockUniswapV2.sol'), 'utf8');

const input = {
  language: 'Solidity',
  sources: {
    'contracts/Kindora.sol': { content: kindoraSource },
    'contracts/mocks/MockUniswapV2.sol': { content: mocksSource }
  },
  settings: {
    optimizer: { enabled: true, runs: 200 },
    outputSelection: {
      '*': {
        '*': ['abi', 'evm.bytecode', 'evm.deployedBytecode']
      }
    }
  }
};

console.log('Compiling contracts...');
const output = JSON.parse(solc.compile(JSON.stringify(input)));

if (output.errors) {
  output.errors.forEach(error => {
    console.error(error.formattedMessage);
  });
  if (output.errors.some(e => e.severity === 'error')) {
    process.exit(1);
  }
}

// Save Kindora artifact
const kindoraContract = output.contracts['contracts/Kindora.sol']['Kindora'];
const kindoraArtifact = {
  _format: 'hh-sol-artifact-1',
  contractName: 'Kindora',
  sourceName: 'contracts/Kindora.sol',
  abi: kindoraContract.abi,
  bytecode: kindoraContract.evm.bytecode.object,
  deployedBytecode: kindoraContract.evm.deployedBytecode.object,
  linkReferences: {},
  deployedLinkReferences: {}
};

fs.writeFileSync(
  path.join(kindoraSolDir, 'Kindora.json'),
  JSON.stringify(kindoraArtifact, null, 2)
);

// Save mock contract artifacts
const mockContracts = ['MockWETH', 'MockPair', 'MockFactory', 'MockRouter', 'RejectingReceiver'];
mockContracts.forEach(contractName => {
  const contract = output.contracts['contracts/mocks/MockUniswapV2.sol'][contractName];
  if (contract) {
    const artifact = {
      _format: 'hh-sol-artifact-1',
      contractName: contractName,
      sourceName: 'contracts/mocks/MockUniswapV2.sol',
      abi: contract.abi,
      bytecode: contract.evm.bytecode.object,
      deployedBytecode: contract.evm.deployedBytecode.object,
      linkReferences: {},
      deployedLinkReferences: {}
    };
    
    fs.writeFileSync(
      path.join(mocksSolDir, `${contractName}.json`),
      JSON.stringify(artifact, null, 2)
    );
  }
});

console.log('✓ Compilation successful!');
console.log('✓ Artifacts generated in:', artifactsDir);
