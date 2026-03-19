pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Nullifier is ERC20 {
    uint256 public queryLimit;
    uint256 public counter;
    bool public revoked;
    
    constructor(uint256 _queryLimit) ERC20("Nullifier", "NULL") {
        queryLimit = _queryLimit;
        counter = 0;
        revoked = false;
    }
    
    function verify(uint256 _tokenId) public view returns (bool) {
        require(!revoked, "Nullifier revoked");
        require(counter < queryLimit, "Query limit reached");
        return true;
    }
    
    function decrementCounter() public {
        require(!revoked, "Nullifier revoked");
        require(counter < queryLimit, "Query limit reached");
        counter++;
        if (counter >= queryLimit) {
            revoked = true;
        }
    }
    
    function revoke() public {
        revoked = true;
    }
}
