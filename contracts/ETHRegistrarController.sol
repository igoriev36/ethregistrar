pragma solidity ^0.5.0;

import "./PriceOracle.sol";
import "./BaseRegistrar.sol";
import "./StringUtils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract ETHRegistrarController is Ownable {
    using StringUtils for *;

    uint constant public MIN_COMMITMENT_AGE = 1 hours;
    uint constant public MAX_COMMITMENT_AGE = 48 hours;
    uint constant public MIN_REGISTRATION_DURATION = 28 days;

    bytes4 constant INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant COMMITMENT_CONTROLLER_ID = bytes4(
        keccak256("rentPrice(string,uint256)") |
        keccak256("available(string)") |
        keccak256("makeCommitment(string,bytes32)") |
        keccak256("commit(bytes32)") |
        keccak256("register(string,address,uint256,bytes32)") |
        keccak256("renew(string,uint256)")
    );

    BaseRegistrar base;
    PriceOracle prices;

    mapping(bytes32=>uint) public commitments;

    event NameRegistered(string name, bytes32 indexed label, address indexed owner, uint cost, uint expires);
    event NameRenewed(string name, bytes32 indexed label, uint cost, uint expires);
    event NewPriceOracle(address indexed oracle);

    constructor(BaseRegistrar _base, PriceOracle _prices) public {
        base = _base;
        prices = _prices;
    }

    function rentPrice(string memory name, uint duration) view public returns(uint) {
        bytes32 hash = keccak256(bytes(name));
        return prices.price(name, base.nameExpires(uint256(hash)), duration);
    }

    function valid(string memory name) public view returns(bool) {
        return name.strlen() > 6;
    }

    function available(string memory name) public view returns(bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function makeCommitment(string memory name, bytes32 secret) pure public returns(bytes32) {
        bytes32 label = keccak256(bytes(name));
        return keccak256(abi.encodePacked(label, secret));
    }

    function commit(bytes32 commitment) public {
        require(commitments[commitment] + MAX_COMMITMENT_AGE < now);
        commitments[commitment] = now;
    }

    function register(string calldata name, address owner, uint duration, bytes32 secret) external payable {
        // Require a valid commitment
        bytes32 commitment = makeCommitment(name, secret);
        require(commitments[commitment] + MIN_COMMITMENT_AGE <= now);

        // If the commitment is too old, or the name is registered, stop
        if(commitments[commitment] + MAX_COMMITMENT_AGE < now || !available(name))  {
            msg.sender.transfer(msg.value);
            return;
        }
        delete(commitments[commitment]);

        uint cost = rentPrice(name, duration);
        require(duration >= MIN_REGISTRATION_DURATION);
        require(msg.value >= cost);

        bytes32 label = keccak256(bytes(name));
        uint expires = base.register(uint256(label), owner, duration);
        emit NameRegistered(name, label, owner, cost, expires);

        if(msg.value > cost) {
            msg.sender.transfer(msg.value - cost);
        }
    }

    function renew(string calldata name, uint duration) external payable {
        uint cost = rentPrice(name, duration);
        require(msg.value >= cost);

        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);

        if(msg.value > cost) {
            msg.sender.transfer(msg.value - cost);
        }

        emit NameRenewed(name, label, cost, expires);
    }

    function setPriceOracle(PriceOracle _prices) public onlyOwner {
        prices = _prices;
        emit NewPriceOracle(address(prices));
    }

    function withdraw() public onlyOwner {
        msg.sender.transfer(address(this).balance);
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == INTERFACE_META_ID ||
               interfaceID == COMMITMENT_CONTROLLER_ID;
    }
}
