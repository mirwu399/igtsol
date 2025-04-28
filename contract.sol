// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ECDSA.sol";
import "./ReentrancyGuard.sol"; // 加上这一行

interface IPancakeRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function WETH() external pure returns (address);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory); // ✅加这一行
}

contract IGTExchangeManager is ReentrancyGuard { // 继承 ReentrancyGuard
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
    ) external nonReentrant {
        require(block.timestamp <= endTime, "Signature expired");
        require(userNonce[msg.sender] == nonce, "Invalid nonce");

        bytes32 hash = keccak256(abi.encodePacked("sell", msg.sender, igtAmount, endTime, nonce));
        emit DebugHash(hash);
        require(_verify(hash, signature), "Invalid signature");

        userNonce[msg.sender]++;

        // 第一步：IGT 换 SYS
        uint256 sysReceived = _swapExactTokens(igtToken, sysToken, igtAmount);
        uint256 halfSys = sysReceived / 2;
        sysQuota[msg.sender] += halfSys;

        // 第二步：一半 SYS 换回 IGT
        uint256 igtReceived = _swapExactTokens(sysToken, igtToken, halfSys);
        igtQuota[msg.sender] += igtReceived;

        emit SellExecuted(msg.sender, igtAmount);
    }

    function _swapExactTokens(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256 beforeBalance = IERC20(tokenOut).balanceOf(address(this));
        uint256 expectedOut = getAmountsOut(tokenIn, tokenOut, amountIn);
        uint256 amountOutMin = expectedOut * 85 / 100; // 允许15%滑点

        IPancakeRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 300
        );

        amountOut = IERC20(tokenOut).balanceOf(address(this)) - beforeBalance;
    }

    function buy(
        uint256 igtAmount,
        uint256 endTime,
        uint256 nonce,
        bytes calldata signature
    ) external nonReentrant { // 加 nonReentrant
        require(block.timestamp <= endTime, "Signature expired");
        require(userNonce[msg.sender] == nonce, "Invalid nonce");

        bytes32 hash = keccak256(abi.encodePacked("buy", msg.sender, igtAmount, endTime, nonce));
        emit DebugHash(hash);
        require(_verify(hash, signature), "Invalid signature");

        userNonce[msg.sender]++;

        address[] memory path = new address[](2);
        path[0] = igtToken;
        path[1] = sysToken;
        uint256 beforeSysBalance = IERC20(sysToken).balanceOf(address(this));
        uint256 expectedOut = getAmountsOut(igtToken, sysToken, igtAmount);
        uint256 amountOutMin = expectedOut * 85 / 100; // 允许5%滑点保护
        IPancakeRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            igtAmount,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 300
        );

        uint256 afterSysBalance = IERC20(sysToken).balanceOf(address(this));
        uint256 sysReceived = afterSysBalance - beforeSysBalance;
        sysQuota[msg.sender] += sysReceived;

        emit BuyExecuted(msg.sender, igtAmount);
    }

    function getAmountsOut(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint256[] memory amounts = IPancakeRouter(router).getAmountsOut(amountIn, path);
        return amounts[1];
    }


    function claim(address token, uint256 amount) external nonReentrant { // 加 nonReentrant
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
        require(IERC20(token).transfer(msg.sender, amount), "Token transfer failed"); // ✅加了 require 检查
        emit Claimed(msg.sender, token, amount);
    }

    function _verify(bytes32 hash, bytes calldata signature) internal view returns (bool) {
        return hash.toEthSignedMessageHash().recover(signature) == signerAddress;
    }
}
