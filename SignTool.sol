// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ECDSA.sol";
contract SignTool is Ownable {

    mapping(address => uint) public userNonce;

    
    constructor() Ownable(msg.sender) {} 
    
 
    

    function verify(bytes32 _msgHash, bytes memory _signature) public view returns (bool) {
        bytes32 _ethSignedMessageHash = ECDSA.toEthSignedMessageHash(_msgHash); 
        return ECDSA.recover(_ethSignedMessageHash, _signature) == owner(); // 👈 改为 owner
    }

}