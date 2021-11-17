pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// VSQPresale
contract VSQPresale is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;

    address public constant fraxAddress = 0x45c32fA6DF82ead1e2EF74d17b76547EDdFaFF89;

    uint256 public salePriceE35 = 0.04 * 1e35;

    uint256 public constant VSQMaximumSupply = 50 * 1e3 * 1e9;

    // We use a counter to defend against people sending VSQ back
    uint256 public VSQRemaining = VSQMaximumSupply;

    uint256 oneHourMatic = 1600;
    uint256 oneDayMatic = oneHourMatic * 24;
    uint256 fourDaysMatic = oneDayMatic * 4;

    uint256 public startBlock;
    uint256 public endBlock;

    mapping(address => uint256) public userVSQTally;
    mapping(address => bool) public whitelist;

    uint256 public remainingBuyers = 0;

    bool public hasRetrievedUnsoldPresale = false;

    address public immutable VSQAddress;

    address public immutable treasuryAddress;


    event VSQPurchased(address sender, uint256 maticSpent, uint256 VSQReceived);
    event StartBlockChanged(uint256 newStartBlock, uint256 newEndBlock);
    event SalePriceE35Changed(uint256 newSalePriceE5);
    event WhitelistEdit(address participant, bool included);
    event RetrieveUnclaimedTokens(uint256 VSQAmount);

    constructor(uint256 _startBlock, address _treasuryAddress, address _VSQAddress) {
        require(block.number < _startBlock, "cannot set start block in the past!");
        require(_treasuryAddress != _VSQAddress, "_treasuryAddress cannot be equal to _VSQAddress");
        require(_treasuryAddress != address(0), "_VSQAddress cannot be the zero address");
        require(_VSQAddress != address(0), "_VSQAddress cannot be the zero address");
    
        startBlock = _startBlock;
        endBlock   = _startBlock + fourDaysMatic;

        VSQAddress = _VSQAddress;
        treasuryAddress = _treasuryAddress;
    }

    function buyVSQ(uint256 fraxToSpend) external nonReentrant {
        require(msg.sender != treasuryAddress, "treasury address cannot partake in presale");
        require(block.number >= startBlock, "presale hasn't started yet, good things come to those that wait");
        require(block.number < endBlock, "presale has ended, come back next time!");
        require(VSQRemaining > 0, "No more VSQ remaining! Come back next time!");
        require(ERC20(VSQAddress).balanceOf(address(this)) > 0, "No more VSQ left! Come back next time!");
        require(fraxToSpend > 0, "not enough frax provided");
        require(whitelist[msg.sender], "presale participant not in the whitelist!");

        uint256 maxVSQPurchase = VSQRemaining / remainingBuyers;

        // maybe useful if we allow people to buy a second time
        //require(userVSQTally[msg.sender] < maxVSQPurchase, "user has already purchased too much VSQ");

        uint256 originalVSQAmountUnscaled = (fraxToSpend * salePriceE35) / 1e35;

        uint256 fraxDecimals = ERC20(fraxAddress).decimals();
        uint256 VSQDecimals = ERC20(VSQAddress).decimals();

        uint256 originalVSQAmount = fraxDecimals == VSQDecimals ?
                                        originalVSQAmountUnscaled :
                                            fraxDecimals > VSQDecimals ?
                                                originalVSQAmountUnscaled / (10 ** (fraxDecimals - VSQDecimals)) :
                                                originalVSQAmountUnscaled * (10 ** (VSQDecimals - fraxDecimals));

        uint256 VSQPurchaseAmount = originalVSQAmount;

        if (VSQPurchaseAmount > maxVSQPurchase)
            VSQPurchaseAmount = maxVSQPurchase;

        // if we dont have enough left, give them the rest.
        if (VSQRemaining < VSQPurchaseAmount)
            VSQPurchaseAmount = VSQRemaining;

        require(VSQPurchaseAmount > 0, "user cannot purchase 0 VSQ");

        // shouldn't be possible to fail these asserts.
        assert(VSQPurchaseAmount <= VSQRemaining);
        require(VSQPurchaseAmount <= ERC20(VSQAddress).balanceOf(address(this)), "not enough VSQ in contract");

        ERC20(VSQAddress).safeTransfer(msg.sender, VSQPurchaseAmount);

        VSQRemaining = VSQRemaining - VSQPurchaseAmount;
        userVSQTally[msg.sender] = userVSQTally[msg.sender] + VSQPurchaseAmount;

        uint256 fraxSpent = fraxToSpend;
        if (VSQPurchaseAmount < originalVSQAmount) {
            fraxSpent = (VSQPurchaseAmount * fraxToSpend) / originalVSQAmount;
        }

        if (fraxSpent > 0)
            ERC20(fraxAddress).safeTransferFrom(msg.sender, treasuryAddress, fraxSpent);

        whitelist[msg.sender] = false;
        if (remainingBuyers > 0)
            remainingBuyers--;

        emit VSQPurchased(msg.sender, fraxSpent, VSQPurchaseAmount);
    }

    function sendUnclaimedsToTreasuryAddress() external onlyOwner {
        require(block.number > endBlock, "presale hasn't ended yet!");
        require(!hasRetrievedUnsoldPresale, "can only recover unsold tokens once!");

        hasRetrievedUnsoldPresale = true;

        uint256 VSQRemainingBalance = ERC20(VSQAddress).balanceOf(address(this));

        require(VSQRemainingBalance > 0, "no more VSQ remaining! you sold out!");

        ERC20(VSQAddress).safeTransfer(treasuryAddress, VSQRemainingBalance);

        emit RetrieveUnclaimedTokens(VSQRemainingBalance);
    }


    function addToWhiteList(address participant, bool included) external onlyOwner {
        require(block.number < startBlock, "cannot change whitelist if sale has already commenced");

        if (whitelist[participant] && !included && remainingBuyers > 0)
            remainingBuyers--;
        else if (!whitelist[participant] && included)
            remainingBuyers++;

        whitelist[participant] = included;

        emit WhitelistEdit(participant, included);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;
        endBlock   = _newStartBlock + fourDaysMatic;

        emit StartBlockChanged(_newStartBlock, endBlock);
    }

    function setSalePriceE35(uint256 _newSalePriceE35) external onlyOwner {
        require(block.number < startBlock - (oneHourMatic * 4), "cannot change price 4 hours before start block");
        require(_newSalePriceE35 >= 0.004 * 1e35, "new price can't be too low");
        require(_newSalePriceE35 <= 0.4 * 1e35, "new price can't be too high");
        salePriceE35 = _newSalePriceE35;

        emit SalePriceE35Changed(salePriceE35);
    }
}