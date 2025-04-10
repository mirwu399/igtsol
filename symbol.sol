// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IPancakeRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

contract SYS {
    string public name = "SYS";
    string public symbol = "SYS";
    uint8 public decimals = 18;
    uint256 public totalSupply = 10_000_000 * 10 ** uint256(decimals);

    address public owner;
    address public taxWallet;
    address public pancakePair;
    IPancakeRouter public router;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    mapping(address => bool) public isTaxExempt;
    mapping(address => bool) public isWhitelist; // Buy whitelist
    bool public buyEnabled = true;

    uint256 public taxPercent = 10;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not admin");
        _;
    }

    constructor(address _router) {
        owner = msg.sender;
        taxWallet = msg.sender;
        router = IPancakeRouter(_router);

        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);

        // 自动创建交易对
        address _pair = IPancakeFactory(router.factory()).createPair(address(this), router.WETH());
        pancakePair = _pair;
    }

    function transfer(address to, uint256 value) public returns (bool) {
        return _transfer(msg.sender, to, value);
    }

    function approve(address spender, uint256 value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(allowance[from][msg.sender] >= value, "Allowance exceeded");
        allowance[from][msg.sender] -= value;
        return _transfer(from, to, value);
    }

    function _transfer(address from, address to, uint256 value) internal returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");

        // 检查是否允许买入
        if (from == pancakePair && !buyEnabled) {
            require(isWhitelist[to], "Buy not enabled");
        }

        uint256 tax = 0;
        if (!isTaxExempt[from] && !isTaxExempt[to]) {
            if (from == pancakePair || to == pancakePair) {
                tax = (value * taxPercent) / 100;
            }
        }

        balanceOf[from] -= value;
        balanceOf[to] += (value - tax);

        if (tax > 0) {
            balanceOf[taxWallet] += tax;
            emit Transfer(from, taxWallet, tax);
        }

        emit Transfer(from, to, value - tax);
        return true;
    }

    // 🛠 设置相关函数
    function setTaxWallet(address _wallet) external onlyOwner {
        taxWallet = _wallet;
    }

    function setTaxExempt(address _addr, bool _status) external onlyOwner {
        isTaxExempt[_addr] = _status;
    }

    function setBuyEnabled(bool _enabled) external onlyOwner {
        buyEnabled = _enabled;
    }

    function setBuyWhitelist(address _addr, bool _status) external onlyOwner {
        isWhitelist[_addr] = _status;
    }

    function setTaxPercent(uint256 _percent) external onlyOwner {
        require(_percent <= 20, "Max 20%");
        taxPercent = _percent;
    }

    function setPancakePair(address _pair) external onlyOwner {
        pancakePair = _pair;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function burn() public returns (bool) {
        uint256 accountBalance = balanceOf[msg.sender];
        require(accountBalance > 0, "No tokens to burn");

        uint256 burnAmount = accountBalance * 5 / 1000; // 千分之 5
        require(burnAmount > 0, "Burn amount too small");

        _burn(msg.sender, burnAmount);
        return true;
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "Burn from zero address");
        require(balanceOf[account] >= amount, "Burn amount exceeds balance");

        balanceOf[account] -= amount;
        totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }
}
