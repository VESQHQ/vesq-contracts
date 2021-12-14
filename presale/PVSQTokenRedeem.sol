pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PVSQTokenRedeem is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public immutable preVSQ;

    address public immutable VSQAddress;

    address public immutable DAO;

    uint256 public startBlock;

    uint256 public constant totalVSQToDistributeTarget = 240934 * 1e9;

    uint256 public cumulativeAllocation = 0;

    uint256 public globalVSQReceivedAsInput = 0;

    mapping(address => uint256) public allocationMap;
    mapping(address => uint256) public redeemedMap;
    mapping(address => bool) public whitelist;

    event VSQSwap(address sender, uint256 amountIn, uint256 amountOut);
    event StartBlockChanged(uint256 newStartBlock);
    event VSQLoaded(address indexed loader, uint256 amount);
    event VSQSkimmed(uint256 amount);
    event TokenSkimmed(uint256 amount);
    event AddToWhitelist(address participant, uint256 indexed allocation);

    constructor(uint256 _startBlock, address _preVSQ, address _VSQAddress, address _DAO) {
        require(block.number < _startBlock, "cannot set start block in the past!");
        require(_preVSQ != _VSQAddress, "preVSQ cannot be equal to VSQ");
        require(_VSQAddress != address(0), "_VSQAddress cannot be the zero address");
        require(_preVSQ != address(0), "_preVSQAddress cannot be the zero address");
        require(_DAO != address(0), "_DAO cannot be the zero address");

        startBlock = _startBlock;

        preVSQ = _preVSQ;
        VSQAddress = _VSQAddress;
        DAO = _DAO;
    }

    function vsqAvailableForUser(address account) public view returns (uint256) {
        uint256 redeemableAllocation = (globalVSQReceivedAsInput * allocationMap[account]) / totalVSQToDistributeTarget;

        return redeemableAllocation - redeemedMap[account];
    }

    function redeemAvailableVSQ() external nonReentrant {
        require(cumulativeAllocation == totalVSQToDistributeTarget, "whitelist is being configured, please stand by!");
        require(block.number >= startBlock, "token redemption hasn't started yet, good things come to those that wait");
        require(whitelist[msg.sender], "you aren't on the pvsq whitelist!");

        uint256 vsqAvailable = vsqAvailableForUser(msg.sender);

        require(redeemedMap[msg.sender] < allocationMap[msg.sender], "You have redeem all of your VSQ allocation, congrats!");
        require(vsqAvailable > 0, "Please come back soon for more VSQ to be made available!");

        uint256 pvsqDecimals = ERC20(preVSQ).decimals();
        uint256 VSQDecimals = ERC20(VSQAddress).decimals();

        uint256 pvsqSwapAmountWei = pvsqDecimals > VSQDecimals ?
                                        vsqAvailable * (10 ** (pvsqDecimals - VSQDecimals)) :
                                            pvsqDecimals < VSQDecimals ?
                                                vsqAvailable / (10 ** (VSQDecimals - pvsqDecimals)) :
                                                vsqAvailable;

        require(pvsqSwapAmountWei > 0, "Please come back soon for more VSQ to be made available!");

        ERC20(preVSQ).safeTransferFrom(msg.sender, BURN_ADDRESS, pvsqSwapAmountWei);

        uint256 VSQSwapAmountWei = pvsqDecimals > VSQDecimals ?
                                        pvsqSwapAmountWei / (10 ** (pvsqDecimals - VSQDecimals)) :
                                            pvsqDecimals < VSQDecimals ?
                                                pvsqSwapAmountWei * (10 ** (VSQDecimals - pvsqDecimals)) :
                                                pvsqSwapAmountWei;

        require(VSQSwapAmountWei > 0, "Please come back soon for more VSQ to be made available!");

        require(IERC20(VSQAddress).balanceOf(address(this)) >= VSQSwapAmountWei, "Not enough tokens in contract for swap");

        ERC20(VSQAddress).safeTransfer(msg.sender, VSQSwapAmountWei);

        redeemedMap[msg.sender] = redeemedMap[msg.sender] + VSQSwapAmountWei;

        emit VSQSwap(msg.sender, VSQSwapAmountWei, pvsqSwapAmountWei);
    }


    function loadVSQToDistribute(uint256 vsqAmount) external nonReentrant {
        require(cumulativeAllocation == totalVSQToDistributeTarget, "whitelist is being configured, please stand by!");
        require(globalVSQReceivedAsInput < totalVSQToDistributeTarget, "pvsq contract has already been fully loaded");

        if (globalVSQReceivedAsInput + vsqAmount > totalVSQToDistributeTarget)
            vsqAmount = totalVSQToDistributeTarget - globalVSQReceivedAsInput;

        ERC20(VSQAddress).safeTransferFrom(msg.sender, address(this), vsqAmount);

        globalVSQReceivedAsInput = globalVSQReceivedAsInput + vsqAmount;

        emit VSQLoaded(msg.sender, vsqAmount);
    }

    // Recover VSQ that was sent in not using the loadVSQToDistribute function.
    function skimUnaccountedVSQToDao() external nonReentrant {
        uint256 vsqBalance = ERC20(VSQAddress).balanceOf(address(this));

        if (vsqBalance > globalVSQReceivedAsInput) {
            uint256 skimAmount = vsqBalance - globalVSQReceivedAsInput;
            ERC20(VSQAddress).safeTransfer(DAO, skimAmount);

            emit VSQSkimmed(skimAmount);
        }
    }

    // Recover any non VSQ that was sent in accidentally.
    function skimTokenToDao(address token) external nonReentrant {
        require(token != VSQAddress, "cannot skim VSQ to DAO this way!");

        uint256 tokenBalance = ERC20(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            ERC20(token).safeTransfer(DAO, tokenBalance);

            emit TokenSkimmed(tokenBalance);
        }
    }

    function addToWhiteList(address participant, uint256 allocation) external onlyOwner {
        require(cumulativeAllocation < totalVSQToDistributeTarget, "whitelist is already configured!");
        require(block.number < startBlock, "cannot change whitelist if sale has already commenced");
        require(participant != DAO, "The DAO cannot claim VSQ");
        require(!whitelist[participant], "already added user to the whitelist!");
        require(allocation >= 10 ** ERC20(VSQAddress).decimals(), "allocation is too small!");

        cumulativeAllocation = cumulativeAllocation + allocation;
        allocationMap[participant] = allocation;

        whitelist[participant] = true;

        require(cumulativeAllocation <= totalVSQToDistributeTarget, "cumulative allocation is over limit!");

        emit AddToWhitelist(participant, allocation);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;

        emit StartBlockChanged(_newStartBlock);
    }
}