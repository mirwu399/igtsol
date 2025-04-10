// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ECDSA.sol";

interface IPancakeRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function WETH() external pure returns (address);
}

contract IGTExchangeManager {
    using ECDSA for bytes32;

    address public owner;
    address public signerAddress;

    address public igtToken;
    address public sysToken;
    address public router;

    mapping(address => uint256) public userNonce;
    mapping(address => uint256) public sysQuota;
    mapping(address => uint256) public igtQuota;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not admin");
        _;
    }

    event SellExecuted(address user, uint amount);
    event BuyExecuted(address user, uint amount);
    event Claimed(address user, address token, uint amount);
    event OwnershipTransferred(address oldOwner, address newOwner);
    event DebugHash(bytes32);

    constructor(
        address _signer,
        address _igtToken,
        address _sysToken,
        address _router
    ) {
        owner = msg.sender;
        signerAddress = _signer;
        igtToken = _igtToken;
        sysToken = _sysToken;
        router = _router;

        // 提前永久授权 IGT 和 SYS 给 Router
        IERC20(igtToken).approve(router, type(uint256).max);
        IERC20(sysToken).approve(router, type(uint256).max);
    }

    function setSigner(address _signer) external onlyOwner {
        signerAddress = _signer;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function sell(
        uint256 igtAmount,
        uint256 endTime,
        uint256 nonce,
        bytes calldata signature
    ) external {
        require(block.timestamp <= endTime, "Signature expired");
        require(userNonce[msg.sender] == nonce, "Invalid nonce");

        bytes32 hash = keccak256(abi.encodePacked("sell", msg.sender, igtAmount, endTime, nonce));
        emit DebugHash(hash); // 需要先在合约顶部添加 event DebugHash(bytes32);
        require(_verify(hash, signature), "Invalid signature");

        userNonce[msg.sender]++;

        address[] memory path = new address[](2);
        path[0] = igtToken;
        path[1] = sysToken;
        uint256 beforeSysBalance = IERC20(sysToken).balanceOf(address(this));
        // 用合约自己的 IGT 买 SYS
        IPancakeRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            igtAmount,
            0,
            path,
            address(this),
            block.timestamp + 300
        );
        uint256 sysReceived = IERC20(sysToken).balanceOf(address(this)) - beforeSysBalance;
        uint256 halfSys = sysReceived / 2;

        sysQuota[msg.sender] += halfSys;

        address[] memory path2 = new address[](2);
        path2[0] = sysToken;
        path2[1] = igtToken;
        uint256 beforeSysBalanceigt = IERC20(igtToken).balanceOf(address(this));
        IPancakeRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            halfSys,
            0,
            path2,
            address(this),
            block.timestamp + 300
        );
        uint256 igtReceived = IERC20(igtToken).balanceOf(address(this)) - beforeSysBalanceigt;
        igtQuota[msg.sender] += igtReceived;

        emit SellExecuted(msg.sender, igtAmount);
    }

    function buy(
        uint256 igtAmount,
        uint256 endTime,
        uint256 nonce,
        bytes calldata signature
    ) external {

        require(block.timestamp <= endTime, "Signature expired");
        require(userNonce[msg.sender] == nonce, "Invalid nonce");

        bytes32 hash = keccak256(abi.encodePacked("buy", msg.sender, igtAmount, endTime, nonce));
        emit DebugHash(hash); // 需要先在合约顶部添加 event DebugHash(bytes32);
        require(_verify(hash, signature), "Invalid signature");

        userNonce[msg.sender]++;

        address[] memory path = new address[](2);
        path[0] = igtToken;
        path[1] = sysToken;
        uint256 beforeSysBalance = IERC20(sysToken).balanceOf(address(this));
        // 用合约自己的 IGT 买 SYS
        IPancakeRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            igtAmount,
            0,
            path,
            address(this),
            block.timestamp + 300
        );
        uint256 afterSysBalance = IERC20(sysToken).balanceOf(address(this));
        uint256 sysReceived = afterSysBalance - beforeSysBalance;
        sysQuota[msg.sender] += sysReceived;

        emit BuyExecuted(msg.sender, igtAmount);
    }

    function claim(address token, uint256 amount) external {
        if (msg.sender != owner) {
            if (token == igtToken) {
                require(igtQuota[msg.sender] >= amount, "Insufficient IGT quota");
                igtQuota[msg.sender] -= amount;
            } else if (token == sysToken) {
                require(sysQuota[msg.sender] >= amount, "Insufficient SYS quota");
                sysQuota[msg.sender] -= amount;
            } else {
                revert("Unsupported token");
            }
        }

        IERC20(token).transfer(msg.sender, amount);
        emit Claimed(msg.sender, token, amount);
    }

    function _verify(bytes32 hash, bytes calldata signature) internal view returns (bool) {
        return hash.toEthSignedMessageHash().recover(signature) == signerAddress;
    }
}
