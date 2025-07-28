// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.28;

import "hardhat/console.sol";

contract BitcoinHeader {{

    struct BlockHeader {{
        uint32 version;
        bytes32 prevBlockHash;
        bytes32 merkleRoot;
        uint32 time;
        uint32 nBits;
    }}

    mapping(bytes32 => BlockHeader) public blockHeaders;
    mapping(bytes32 => uint256) public chainWorks;

    bytes constant GENESIS_HEADER = hex"{blockheader_serialisation}";
    
    bytes32 public bestBlockHash;
    uint256 public bestWork;

    bytes32 GENESIS_BLOCKHASH = sha256(abi.encodePacked(sha256(GENESIS_HEADER)));

    constructor() {{
        blockHeaders[GENESIS_BLOCKHASH] = processHeader(GENESIS_HEADER);
        chainWorks[GENESIS_BLOCKHASH] = {genesis_chain_work};
        bestBlockHash = GENESIS_BLOCKHASH;
        bestWork = chainWorks[GENESIS_BLOCKHASH];
    }}

    function processHeader(bytes memory header) public pure returns (BlockHeader memory blockHeader) {{
        require(header.length == 80, "Header must be 80 bytes");
        // Version (4 bytes, little-endian)
        blockHeader.version = uint32(uint8(header[0]))
            | (uint32(uint8(header[1])) << 8)
            | (uint32(uint8(header[2])) << 16)
            | (uint32(uint8(header[3])) << 24);

        // Previous block hash (32 bytes)
        blockHeader.prevBlockHash = bytes32(slice(header, 4, 32));

        // Merkle root (32 bytes)
        blockHeader.merkleRoot = bytes32(slice(header, 36, 32));

        // Time (4 bytes, little-endian)
        blockHeader.time = uint32(uint8(header[68]))
            | (uint32(uint8(header[69])) << 8)
            | (uint32(uint8(header[70])) << 16)
            | (uint32(uint8(header[71])) << 24);

        // nBits (4 bytes, little-endian)
        blockHeader.nBits = uint32(uint8(header[72]))
            | (uint32(uint8(header[73])) << 8)
            | (uint32(uint8(header[74])) << 16)
            | (uint32(uint8(header[75])) << 24);
        
         return blockHeader;
    }}

    // Helper: slice bytes array
    function slice(bytes memory data, uint start, uint len) internal pure returns (bytes memory) {{
        require(data.length >= start + len, "Slice out of bounds");
        bytes memory out = new bytes(len);
        for (uint i = 0; i < len; i++) {{
            out[i] = data[start + i];
        }}
        return out;
    }}

    function doubleSha(bytes memory data) public pure returns (bytes32 hash) {{
        return sha256(abi.encodePacked(sha256(data)));
    }}

    event HeaderAccepted(bytes32 indexed blockHash, uint256 totalWork);

    //event HeaderAccepted(bytes32 indexed blockHash);  
    
    function submitHeader(bytes calldata header) external {{
        require(header.length == 80, "Invalid header length");
        bytes memory headerMem = header;

        BlockHeader memory submittedBlockHeader = processHeader(headerMem); 

        require(
            blockHeaders[submittedBlockHeader.prevBlockHash].version != 0,
            "Previous block not found"
        );

        bytes32 blockHashBE = sha256(abi.encodePacked(sha256(headerMem)));
        bytes32 blockHashLE = reverseEndianness(blockHashBE);
        uint256 totalWork = estimateWork(submittedBlockHeader.nBits, blockHashLE, submittedBlockHeader.prevBlockHash);
        console.log("total work:", totalWork);
        console.log("best work:", bestWork);
        require(totalWork > bestWork,"not enough PoW");
        blockHeaders[blockHashBE] = submittedBlockHeader;
        bestBlockHash = blockHashBE;
        chainWorks[blockHashBE] = totalWork;
        bestWork = totalWork;
        emit HeaderAccepted(blockHashBE, totalWork);

        // else: do nothing (block is ignored)
    }}

    function estimateWork(uint32 nBits, bytes32 blockHash, bytes32 prevBlockHash) public view returns (uint256 work) {{
        uint8 exponent = uint8(nBits >> 24);
        uint32 coefficient = nBits & 0xFFFFFF;
        uint256 target = uint256(coefficient) * (2 ** (8 * (exponent - 3)));
        uint256 hashVal = uint256(blockHash);
        require(hashVal <= target, "block hash does not meet target");
        require(target < type(uint256).max, "Target too large");
        // 2^256 is 1 << 256, but since uint256 can't represent 2^256, use max value + 1
        // So, expectedHashes = (2^256 - 1) / (target + 1) + 1
        // To avoid overflow, use type(uint256).max (which is 2^256 - 1)
        uint256 expectedWork = (type(uint256).max) / (target + 1) + 1;
        console.log("expected work", expectedWork);
        uint256 totalWork = chainWorks[prevBlockHash]+expectedWork;
        console.log("totalWork", totalWork);
        return totalWork;
    }}


    function reverseEndianness(bytes32 input) public pure returns (bytes32 result) {{
        unchecked {{
            for (uint256 i = 0; i < 32; i++) {{
                result |= (input & bytes32(0xFF << (i * 8))) >> (i * 8) << ((31 - i) * 8);
            }}
        }}
    }}

    function verifyMerkleProof(
        bytes32[] memory proof,
        bytes32 blockHash,
        bytes32 leaf,
        bool[] memory positions
     ) public view returns (bool) {{
        require(proof.length == positions.length, "Proof and positions length mismatch");
        bytes32 computed = leaf;
        console.logBytes32(computed);
        for (uint256 i = 0; i < proof.length; ++i) {{
            bytes32 sibling = proof[i];
            console.logBytes32(sibling);
            if (positions[i]) {{
                // Computed hash is on the right
                computed = sha256(abi.encodePacked(sha256(abi.encodePacked(sibling, computed))));
            }} else {{
                // Computed hash is on the left
                computed = sha256(abi.encodePacked(sha256(abi.encodePacked(computed, sibling))));
            }}
            console.logBytes32(computed);

        }}
        console.logBytes32(computed);
        return computed == blockHeaders[blockHash].merkleRoot;
    }}
}}
