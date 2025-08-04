---
title: 从ERC20 USDT分析区块链合约原理
date: 2025-11-15 10:00:00
tags:
  - Web3.0
  - Ethereum
  - ERC20
categories: Web3.0
cover: https://imgloc.com/image/CapKLY
---

# 加密货币和稳定币

加密货币（Cryptocurrency）又经常被称为加密资产（Crypto Asset），是指在区块链技术上运行的数字资产，如比特币（Bitcoin）、以太坊（Ethereum）等，同时也衍生出其他类型的加密资产，如 NFT（非同质化代币）等。此类货币相对于现实世界无固定的锚点，其价值由市场供需决定，且由于区块出块难度调整、市场流动性等因素，价格会有较大波动。为了解决这一问题，市场衍生出了稳定币（Stablecoin）。

稳定币（Stablecoin）是指通过特定机制保持价值相对稳定的加密货币，通常与法定货币（如美元、欧元）挂钩。目前市场上常见的稳定币包括 USDT（Tether）、USDC（USD Coin）等。根据发行机制不同，稳定币主要可分为三类：法币抵押型、加密资产抵押型和算法稳定币。以 USDT 为例，它属于法币抵押型稳定币，由 Tether 公司发行，理论上每发行 1 枚 USDT，Tether 应持有价值 1 美元的储备资产（包括现金、债券等），形成 1:1 的锚定关系，用户理论上可以随时用 1 USDT 兑换 1 美元。

# 多链问题解决

了解区块链的玩家都知道，目前主流的公链有很多种，数字资产在发行时会选择在一个链或是多个链上发行。例如，USDT（Tether）就选择在多个链上发行，包括以太坊（Ethereum）、波卡（Polkadot）、卡普（Kucoin）等，但像 OKB 这一类的平台币，通常只在 OK 链（OKChain）上发行。

在不同的链上发行数字货币，其实本质上就是在不同的链上部署一个智能合约，如 USDT 在 Tron 链的合约地址[TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t](https://tronscan.org/#/token20/TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t)，在以太坊链上的合约地址[0xdAC17F958D2ee523a2206206994597C13D831ec7](https://etherscan.io/address/0xdAC17F958D2ee523a2206206994597C13D831ec7)。从合约地址可以看出，USDT 在不同链上的合约地址是不同的，这是因为每个链都有自己的地址空间，合约地址在不同链上是唯一的。

当然，无论在哪个链上购买数字资产，理论上所有链的同名数字资产都是等价的，用户如果希望在不同链上进行资产转移，通常需要通过跨链桥（Cross-Chain Bridge）来实现。跨链桥是一种特殊的合约，用于在不同链之间进行资产的转移和交互，在进行交易时需要支付一笔跨链手续费。

有人可能也会疑惑，在交易所充值 UDST 时，为什么只有在充值时需要选择充值的链，而充值完成后却不显示自己充值的货币属于哪个链。其实是因为，目前交易所都是用的内部记账的方式，用户只需要在充值时选择交易链，交易所收到充值金额后会向用户的账户上划拨对应的金额。其实本质上来说充值到交易所的数字货币是托管在交易所的，真实的 Token 资产并不在用户手里（这时候的余额其实就是数据库里的一串数字）。当用户需要提取加密货币时，用户可以选择任意的交易链（其实可以认为用户的数字资产在交易所实现了无痛跨链转换）。

# 智能合约原理分析

从区块链的原理来看，数字货币本质上就是一个智能合约。智能合约是运行在区块链 EVM 上的程序，通常由 solidity 语言、go 语言、rust 等语言编写，这里以 ERC20 USDT 合约为例，分析一下 USDT 合约的原理。

## 名词和术语

区块链可以类比到普通业务应用，只不过区块链业务时去中心化的，节点之间通过共识机制进行通信。用户和区块链交互一般都是通过 RPC 接口调用合约（和普通业务应用的 API 接口类似），合约通常有多个接口函数，在区块链中被称为 ABI（Application Binary Interface）。每个接口函数都有一个函数签名，用于唯一标识该函数。合约的状态变量（如余额、授权等）通常存储在合约的存储区域（Storage）中，而函数参数和局部变量则存储在合约的内存区域（Memory）中。

## 合约标准

和普通业务应用一样，智能合约也有类似 Restful 一样的接口规范，如：

### ERC20 标准

ERC20 时以太坊上最常见的合约标准，其定义了以下一些函数

- 账户余额(balanceOf())
- 转账(transfer())
- 授权转账(transferFrom())
- 授权(approve())
- 代币总供给(totalSupply())
- 授权转账额度(allowance())
- 代币信息（可选）：名称(name())，代号(symbol())，小数位数(decimals())

其对应一个接口规范 IERC20，其定义如下：

```solidity
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
```

### ERC721 标准

ERC721 是以太坊上最常见的非同质化代币（NFT）合约标准，其对应一个接口规范 IERC721，其定义如下：

```solidity
interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) external view returns (uint256 balance);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function approve(address to, uint256 tokenId) external;

    function setApprovalForAll(address operator, bool _approved) external;

    function getApproved(uint256 tokenId) external view returns (address operator);

    function isApprovedForAll(address owner, address operator) external view returns (bool);
}
```

可以对比 ERC20 标准，可以发现 ERC721 标准多出一个 tokenId 参数，其本质原因来源于 NFT 的特殊性。ERC20 代币都时同质化代币，也就是所有代币（Token）是相同的，就好比 1 美元，无论多少张这个钱的设计以及价值都是一样的。但是 ERC721 代币不同，每个代币都会携带不同的元数据（Metadata），可以类比成纪念银币，这个代币合约类比到一批银币，合约铸造出不同的代币对应到不同的银币，每个银币都是独一无二的。

## USDT 合约分析

有了上述的基础知识，可以开始看 UDST 的合约代码了。

### 代币主合约

```solidity
pragma solidity ^0.4.17;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address public owner;

    /**
      * @dev The Ownable constructor sets the original `owner` of the contract to the sender
      * account.
      */
    function Ownable() public {
        owner = msg.sender;
    }

    /**
      * @dev Throws if called by any account other than the owner.
      */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
    * @dev Allows the current owner to transfer control of the contract to a newOwner.
    * @param newOwner The address to transfer ownership to.
    */
    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
    }

}

/**
 * @title ERC20Basic
 * @dev Simpler version of ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20Basic {
    uint public _totalSupply;
    function totalSupply() public constant returns (uint);
    function balanceOf(address who) public constant returns (uint);
    function transfer(address to, uint value) public;
    event Transfer(address indexed from, address indexed to, uint value);
}

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {
    function allowance(address owner, address spender) public constant returns (uint);
    function transferFrom(address from, address to, uint value) public;
    function approve(address spender, uint value) public;
    event Approval(address indexed owner, address indexed spender, uint value);
}

/**
 * @title Basic token
 * @dev Basic version of StandardToken, with no allowances.
 */
contract BasicToken is Ownable, ERC20Basic {
    using SafeMath for uint;

    mapping(address => uint) public balances;

    // additional variables for use if transaction fees ever became necessary
    uint public basisPointsRate = 0;
    uint public maximumFee = 0;

    /**
    * @dev Fix for the ERC20 short address attack.
    */
    modifier onlyPayloadSize(uint size) {
        require(!(msg.data.length < size + 4));
        _;
    }

    /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint _value) public onlyPayloadSize(2 * 32) {
        uint fee = (_value.mul(basisPointsRate)).div(10000);
        if (fee > maximumFee) {
            fee = maximumFee;
        }
        uint sendAmount = _value.sub(fee);
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(sendAmount);
        if (fee > 0) {
            balances[owner] = balances[owner].add(fee);
            Transfer(msg.sender, owner, fee);
        }
        Transfer(msg.sender, _to, sendAmount);
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the the balance of.
    * @return An uint representing the amount owned by the passed address.
    */
    function balanceOf(address _owner) public constant returns (uint balance) {
        return balances[_owner];
    }

}

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * @dev https://github.com/ethereum/EIPs/issues/20
 * @dev Based oncode by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is BasicToken, ERC20 {

    mapping (address => mapping (address => uint)) public allowed;

    uint public constant MAX_UINT = 2**256 - 1;

    /**
    * @dev Transfer tokens from one address to another
    * @param _from address The address which you want to send tokens from
    * @param _to address The address which you want to transfer to
    * @param _value uint the amount of tokens to be transferred
    */
    function transferFrom(address _from, address _to, uint _value) public onlyPayloadSize(3 * 32) {
        var _allowance = allowed[_from][msg.sender];

        // Check is not needed because sub(_allowance, _value) will already throw if this condition is not met
        // if (_value > _allowance) throw;

        uint fee = (_value.mul(basisPointsRate)).div(10000);
        if (fee > maximumFee) {
            fee = maximumFee;
        }
        if (_allowance < MAX_UINT) {
            allowed[_from][msg.sender] = _allowance.sub(_value);
        }
        uint sendAmount = _value.sub(fee);
        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(sendAmount);
        if (fee > 0) {
            balances[owner] = balances[owner].add(fee);
            Transfer(_from, owner, fee);
        }
        Transfer(_from, _to, sendAmount);
    }

    /**
    * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
    * @param _spender The address which will spend the funds.
    * @param _value The amount of tokens to be spent.
    */
    function approve(address _spender, uint _value) public onlyPayloadSize(2 * 32) {

        // To change the approve amount you first have to reduce the addresses`
        //  allowance to zero by calling `approve(_spender, 0)` if it is not
        //  already 0 to mitigate the race condition described here:
        //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        require(!((_value != 0) && (allowed[msg.sender][_spender] != 0)));

        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
    }

    /**
    * @dev Function to check the amount of tokens than an owner allowed to a spender.
    * @param _owner address The address which owns the funds.
    * @param _spender address The address which will spend the funds.
    * @return A uint specifying the amount of tokens still available for the spender.
    */
    function allowance(address _owner, address _spender) public constant returns (uint remaining) {
        return allowed[_owner][_spender];
    }

}


/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
  event Pause();
  event Unpause();

  bool public paused = false;


  /**
   * @dev Modifier to make a function callable only when the contract is not paused.
   */
  modifier whenNotPaused() {
    require(!paused);
    _;
  }

  /**
   * @dev Modifier to make a function callable only when the contract is paused.
   */
  modifier whenPaused() {
    require(paused);
    _;
  }

  /**
   * @dev called by the owner to pause, triggers stopped state
   */
  function pause() onlyOwner whenNotPaused public {
    paused = true;
    Pause();
  }

  /**
   * @dev called by the owner to unpause, returns to normal state
   */
  function unpause() onlyOwner whenPaused public {
    paused = false;
    Unpause();
  }
}

contract BlackList is Ownable, BasicToken {

    /////// Getters to allow the same blacklist to be used also by other contracts (including upgraded Tether) ///////
    function getBlackListStatus(address _maker) external constant returns (bool) {
        return isBlackListed[_maker];
    }

    function getOwner() external constant returns (address) {
        return owner;
    }

    mapping (address => bool) public isBlackListed;

    function addBlackList (address _evilUser) public onlyOwner {
        isBlackListed[_evilUser] = true;
        AddedBlackList(_evilUser);
    }

    function removeBlackList (address _clearedUser) public onlyOwner {
        isBlackListed[_clearedUser] = false;
        RemovedBlackList(_clearedUser);
    }

    function destroyBlackFunds (address _blackListedUser) public onlyOwner {
        require(isBlackListed[_blackListedUser]);
        uint dirtyFunds = balanceOf(_blackListedUser);
        balances[_blackListedUser] = 0;
        _totalSupply -= dirtyFunds;
        DestroyedBlackFunds(_blackListedUser, dirtyFunds);
    }

    event DestroyedBlackFunds(address _blackListedUser, uint _balance);

    event AddedBlackList(address _user);

    event RemovedBlackList(address _user);

}

contract UpgradedStandardToken is StandardToken{
    // those methods are called by the legacy contract
    // and they must ensure msg.sender to be the contract address
    function transferByLegacy(address from, address to, uint value) public;
    function transferFromByLegacy(address sender, address from, address spender, uint value) public;
    function approveByLegacy(address from, address spender, uint value) public;
}

contract TetherToken is Pausable, StandardToken, BlackList {

    string public name;
    string public symbol;
    uint public decimals;
    address public upgradedAddress;
    bool public deprecated;

    //  The contract can be initialized with a number of tokens
    //  All the tokens are deposited to the owner address
    //
    // @param _balance Initial supply of the contract
    // @param _name Token Name
    // @param _symbol Token symbol
    // @param _decimals Token decimals
    function TetherToken(uint _initialSupply, string _name, string _symbol, uint _decimals) public {
        _totalSupply = _initialSupply;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        balances[owner] = _initialSupply;
        deprecated = false;
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function transfer(address _to, uint _value) public whenNotPaused {
        require(!isBlackListed[msg.sender]);
        if (deprecated) {
            return UpgradedStandardToken(upgradedAddress).transferByLegacy(msg.sender, _to, _value);
        } else {
            return super.transfer(_to, _value);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function transferFrom(address _from, address _to, uint _value) public whenNotPaused {
        require(!isBlackListed[_from]);
        if (deprecated) {
            return UpgradedStandardToken(upgradedAddress).transferFromByLegacy(msg.sender, _from, _to, _value);
        } else {
            return super.transferFrom(_from, _to, _value);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function balanceOf(address who) public constant returns (uint) {
        if (deprecated) {
            return UpgradedStandardToken(upgradedAddress).balanceOf(who);
        } else {
            return super.balanceOf(who);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function approve(address _spender, uint _value) public onlyPayloadSize(2 * 32) {
        if (deprecated) {
            return UpgradedStandardToken(upgradedAddress).approveByLegacy(msg.sender, _spender, _value);
        } else {
            return super.approve(_spender, _value);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function allowance(address _owner, address _spender) public constant returns (uint remaining) {
        if (deprecated) {
            return StandardToken(upgradedAddress).allowance(_owner, _spender);
        } else {
            return super.allowance(_owner, _spender);
        }
    }

    // deprecate current contract in favour of a new one
    function deprecate(address _upgradedAddress) public onlyOwner {
        deprecated = true;
        upgradedAddress = _upgradedAddress;
        Deprecate(_upgradedAddress);
    }

    // deprecate current contract if favour of a new one
    function totalSupply() public constant returns (uint) {
        if (deprecated) {
            return StandardToken(upgradedAddress).totalSupply();
        } else {
            return _totalSupply;
        }
    }

    // Issue a new amount of tokens
    // these tokens are deposited into the owner address
    //
    // @param _amount Number of tokens to be issued
    function issue(uint amount) public onlyOwner {
        require(_totalSupply + amount > _totalSupply);
        require(balances[owner] + amount > balances[owner]);

        balances[owner] += amount;
        _totalSupply += amount;
        Issue(amount);
    }

    // Redeem tokens.
    // These tokens are withdrawn from the owner address
    // if the balance must be enough to cover the redeem
    // or the call will fail.
    // @param _amount Number of tokens to be issued
    function redeem(uint amount) public onlyOwner {
        require(_totalSupply >= amount);
        require(balances[owner] >= amount);

        _totalSupply -= amount;
        balances[owner] -= amount;
        Redeem(amount);
    }

    function setParams(uint newBasisPoints, uint newMaxFee) public onlyOwner {
        // Ensure transparency by hardcoding limit beyond which fees can never be added
        require(newBasisPoints < 20);
        require(newMaxFee < 50);

        basisPointsRate = newBasisPoints;
        maximumFee = newMaxFee.mul(10**decimals);

        Params(basisPointsRate, maximumFee);
    }

    // Called when new token are issued
    event Issue(uint amount);

    // Called when tokens are redeemed
    event Redeem(uint amount);

    // Called when contract is deprecated
    event Deprecate(address newAddress);

    // Called if contract ever adds fees
    event Params(uint feeBasisPoints, uint maxFee);
}
```

### 可升级合约

看到代币的主合约 TetherToken 中，在 Storage 中定义了两个比较特殊的变量：

```solidity
bool public deprecated;
address public upgradedAddress;
```

在看到转账函数，有一个判断 deprecated 的逻辑：

```solidity
if (deprecated) {
    return UpgradedStandardToken(upgradedAddress).transferByLegacy(msg.sender, _to, _value);
} else {
    return super.transfer(_to, _value);
}
```

这是一个开关式的代理合约设计，在默认状态下，合约代理是关闭的，调用转账函数时会通过 super 调用到 BasicToken 中的转账函数，当有需求时，可以调用 ABI `function deprecate(address _upgradedAddress) public onlyOwner`启用代理合约并设置底层合约地址。

为什么要这样设计呢？其实本质就在于区块链的不可篡改性，合约被部署后时被打包到区块中的，无法发布更新，但是 storage 中的数据是可以通过调用合约修改的，使用这种方式可以做到入口合约地址不变，更新代币合约逻辑。

### 授权转账（区块链特有的转账方式）

授权转账和普通转账不同。普通转账，用户只能通过自己的账户向他人进行转账，而授权转账时，只要被授权用户获得他人钱包的授权，用户就可以直接通过授权转账的方式转出他人资产。

```solidity
mapping (address => mapping (address => uint)) public allowed;

function approve(address _spender, uint _value) public onlyPayloadSize(2 * 32) {
    // To change the approve amount you first have to reduce the addresses`
    //  allowance to zero by calling `approve(_spender, 0)` if it is not
    //  already 0 to mitigate the race condition described here:
    //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    require(!((_value != 0) && (allowed[msg.sender][_spender] != 0)));

    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
}
function allowance(address _owner, address _spender) public constant returns (uint remaining) {
    return allowed[_owner][_spender];
}

function transferFrom(address _from, address _to, uint _value) public onlyPayloadSize(3 * 32) {
    var _allowance = allowed[_from][msg.sender];

    // Check is not needed because sub(_allowance, _value) will already throw if this condition is not met
    // if (_value > _allowance) throw;

    uint fee = (_value.mul(basisPointsRate)).div(10000);
    if (fee > maximumFee) {
        fee = maximumFee;
    }
    if (_allowance < MAX_UINT) {
        allowed[_from][msg.sender] = _allowance.sub(_value);
    }
    uint sendAmount = _value.sub(fee);
    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(sendAmount);
    if (fee > 0) {
        balances[owner] = balances[owner].add(fee);
        Transfer(_from, owner, fee);
    }
    Transfer(_from, _to, sendAmount);
}
```

用户的授权信息时被存到 allowed 映射中，key 是被授权用户的地址，value 是一个映射，key 是授权用户的地址，value 是授权的金额。钱包主人使用`function approve(address _spender, uint _value) public onlyPayloadSize(2 * 32)`授权给 \_spender 地址转账 \_value 金额的能力，授权数据被存储在 allowed 映射中。

可以看到上面的`function transferFrom(address _from, address _to, uint _value) public onlyPayloadSize(3 * 32)`中，转账会先获取调用者（msg.sender）针对 \_from 地址的授权金额 \_allowance，然后判断是否足够转账，不足则抛出异常。

### Ownable

Ownable 是合约中重要的管理合约。当合约部署时，Ownable 合约将会把合约部署者的地址存放到 owner 变量中。Ownable 合约中的 onlyOwner()，相当于一个权限校验中间件，在部分 ABI 调用前会先运行以校验用户的操作是否合法。

```solidity
modifier onlyOwner() {
    require(msg.sender == owner);
    _;
}
```
