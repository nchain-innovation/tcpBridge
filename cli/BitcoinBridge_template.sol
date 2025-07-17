// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "hardhat/console.sol";

// Interface for Merkle proof verification (to be implemented or imported)
interface IMerkleVerifier {{
    function verifyMerkleProof(
        bytes32[] calldata proof,
        bytes32 bitcoinBlockHash,
        bytes32 leaf,
        bool[] calldata positions
    ) external view returns (bool);
}}

contract BitcoinBridge {{
    struct BitcoinTransactionPair {{
        bytes32 mintTxId;
        bytes32 verificationTxId;
        uint256 ethAmount;
        bool isBacked;
    }}

    // Mapping from mintTxId to transaction pair
    mapping(bytes32 => BitcoinTransactionPair) public txPairs;

    // Hardcoded Merkle verifier contract address (replace with your deployed verifier address)
    address private constant MERKLE_VERIFIER_ADDRESS = {oracle_contract_address};
    IMerkleVerifier public constant merkleVerifier = IMerkleVerifier(MERKLE_VERIFIER_ADDRESS);

    event UnbackedPairAdded(bytes32 indexed mintTxId, bytes32 indexed verificationTxId);
    event PairFunded(bytes32 indexed mintTxId, uint256 amount);
    event Pegout(
        bytes32 indexed mintTxId,
        address indexed ethAddress,
        uint256 amount
    );

    // Add a new unbacked pair
    function addUnbackedPair(bytes32 mintTxId, bytes32 verificationTxId) external {{
        require(txPairs[mintTxId].mintTxId == 0, "Pair already exists");
        txPairs[mintTxId] = BitcoinTransactionPair(mintTxId, verificationTxId, 0, false);
        emit UnbackedPairAdded(mintTxId, verificationTxId);
    }}

    // Fund a pair, moving it to the backed pool
    function fundPair(bytes32 mintTxId) external payable {{
        BitcoinTransactionPair storage pair = txPairs[mintTxId];
        require(pair.mintTxId != 0, "Pair does not exist");
        require(!pair.isBacked, "Already funded");
        require(msg.value > 0, "No ETH sent");
        pair.ethAmount = msg.value;
        pair.isBacked = true;
        emit PairFunded(mintTxId, msg.value);
    }}

    function sha256d(bytes memory data) public pure returns (bytes32 hash) {{
        return sha256(abi.encodePacked(sha256(data)));
    }}

    
    function truncateHex(bytes calldata input) public pure returns (bytes32 firstPart, bytes32 lastPart) {{
        require(input.length >= 37 + 36, "Input too short");

        // Extract first 37 bytes, then remove first 5 bytes
        bytes memory first37 = new bytes(37);
        for (uint i = 0; i < 37; i++) {{
            first37[i] = input[i];
        }}
        bytes memory _firstPart = new bytes(32); // 37 - 5 = 32
        for (uint i = 0; i < 32; i++) {{
            _firstPart[i] = first37[i + 5];
        }}
        firstPart = bytes32(_firstPart);

        // Extract last 36 bytes, then remove last 4 bytes
        bytes memory last36 = new bytes(36);
        for (uint i = 0; i < 36; i++) {{
            last36[i] = input[input.length - 36 + i];
        }}
        bytes memory _lastPart = new bytes(32); // 36 - 4 = 32
        for (uint i = 0; i < 32; i++) {{
            _lastPart[i] = last36[i];
        }}
        lastPart = bytes32(_lastPart);
        // last 4 bytes are simply omitted
    }}

    function reverseEndianness(bytes32 input) public pure returns (bytes32 result) {{
        unchecked {{
            for (uint256 i = 0; i < 32; i++) {{
                result |= (input & bytes32(0xFF << (i * 8))) >> (i * 8) << ((31 - i) * 8);
            }}
        }}
    }}

    function pegout(
        bytes calldata serializedBitcoinTx,
        bytes32[] calldata merkleProof,
        bytes32 bitcoinBlockHash,
        bool[] calldata positions,
        bytes32 mintTxId
    ) external {{
        BitcoinTransactionPair storage pair = txPairs[mintTxId];
        require(pair.isBacked, "Not backed");

        (bytes32 prevTxId, bytes32 recipient) = truncateHex(serializedBitcoinTx);

        address ethAddress = address(uint160(uint256(recipient)));

        require(reverseEndianness(prevTxId) == pair.verificationTxId, "Input txid mismatch");

        bytes32 txHash = sha256d(serializedBitcoinTx);

        console.logBytes32(txHash);

        // Verify Merkle proof via external contract
        bool proofValid = merkleVerifier.verifyMerkleProof(merkleProof, bitcoinBlockHash, txHash, positions);
        require(proofValid, "Invalid Merkle proof");

        require(ethAddress != address(0), "Invalid recipient");

        // Send ETH and clear balance
        uint256 amount = pair.ethAmount;
        pair.ethAmount = 0;
        (bool sent, ) = ethAddress.call{{value: amount}}("");
        require(sent, "ETH transfer failed");
        delete txPairs[mintTxId];

        emit Pegout(mintTxId, ethAddress, amount);
    }}

    // Fallback to receive ETH
    receive() external payable {{}}
}}
