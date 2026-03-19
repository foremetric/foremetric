pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Nullifier.sol";

contract TestNullifier is ERC20 {
    Nullifier public nullifier;
    
    constructor() ERC20("TestNullifier", "TNULL") {
        nullifier = new Nullifier(3);
    }
    
    function testVerify() public view returns (bool) {
        return nullifier.verify(1);
    }
    
    function testDecrement() public {
        nullifier.decrementCounter();
    }
    
    function testRevoke() public {
        nullifier.revoke();
    }
}
