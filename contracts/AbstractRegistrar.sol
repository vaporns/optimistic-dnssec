pragma solidity ^0.4.24;

import "@ensdomains/ENS/contracts/ENS.sol";
import "@ensdomains/dnssec-oracle/contracts/DNSSEC.sol";
import "@ensdomains/dnssec-oracle/contracts/BytesUtils.sol";
import "@ensdomains/dnsregistrar/contracts/DNSClaimChecker.sol";

contract AbstractRegistrar {

    using BytesUtils for bytes;

    struct Record {
        address submitter;
        address newOwner;
        bytes32 proof;
        bytes32 name;
        uint256 submitted;
    }

    uint16 constant CLASS_INET = 1;
    uint16 constant TYPE_TXT = 16;

    ENS public ens;
    DNSSEC public oracle;

    uint256 public cooldown;
    uint256 public stake;

    /// label => record
    mapping (bytes32 => Record) public records;

    event Submitted(bytes32 indexed node, address indexed owner, bytes proof, bytes dnsname);
    event Claim(bytes32 indexed node, address indexed owner);
    event Challenged(bytes32 indexed node, address indexed challenger);

    constructor(ENS _ens, DNSSEC _dnssec, uint256 _cooldown, uint256 _stake) public {
        ens = _ens;
        oracle = _dnssec;
        cooldown = _cooldown;
        stake = _stake;
    }

    /// @notice This function allows the user to submit a DNSSEC proof for a certain amount of ETH.
    function _submit(bytes name, bytes proof, address newOwner) internal {
        bytes32 label;
        bytes32 node;
        (label, node) = DNSClaimChecker.getLabels(name);

        bytes32 namehash = keccak256(abi.encodePacked(node, label));

        records[namehash] = Record({
            submitter: msg.sender,
            newOwner: newOwner,
            proof: keccak256(proof),
            name: keccak256(name),
            submitted: now
        });

        emit Submitted(namehash, newOwner, proof, name);
    }

    // @notice This function commits a Record to the ENS registry.
    function _commit(bytes name) internal returns (bytes32) {
        bytes32 label;
        bytes32 node;
        (label, node) = DNSClaimChecker.getLabels(name);

        bytes32 domain = keccak256(abi.encodePacked(node, label));
        Record storage record = records[domain];

        require(record.submitted + cooldown <= now);

        address newOwner = record.newOwner;

        require(newOwner != address(0x0));

        ens.setSubnodeOwner(node, label, newOwner);

        emit Claim(domain, newOwner);

        return domain;
    }

    /// @notice This function allows a user to challenge the validity of a DNSSEC proof submitted.
    function _challenge(bytes32 node, bytes proof, bytes name) internal {
        Record storage record = records[node];

        require(record.submitted + cooldown > now);

        require(record.proof == keccak256(proof));
        require(record.name == keccak256(name));

        require(record.newOwner != DNSClaimChecker.getOwnerAddress(oracle, name, proof));

        delete records[node];
        msg.sender.transfer(stake);

        emit Challenged(node, msg.sender);
    }
}
