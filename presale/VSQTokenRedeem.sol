pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VSQTokenRedeem is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public immutable preVSQ;

    address public immutable VSQAddress;

    uint256 public startBlock;

    event VSQSwap(address sender, uint256 amountIn, uint256 amountOut);
    event StartBlockChanged(uint256 newStartBlock);

    constructor(uint256 _startBlock, address _preVSQ, address _VSQAddress) {
        require(block.number < _startBlock, "cannot set start block in the past!");
        require(_preVSQ != _VSQAddress, "preVSQ cannot be equal to VSQ");
        require(_VSQAddress != address(0), "_VSQAddress cannot be the zero address");
        require(_preVSQ != address(0), "_preVSQAddress cannot be the zero address");

        startBlock = _startBlock;

        preVSQ = _preVSQ;
        VSQAddress = _VSQAddress;
    }

    function swapPreVSQForVSQ(uint256 VSQSwapAmount) external nonReentrant {
        require(block.number >= startBlock, "token redemption hasn't started yet, good things come to those that wait");

        uint256 pvsqDecimals = ERC20(preVSQ).decimals();
        uint256 VSQDecimals = ERC20(VSQAddress).decimals();

        uint256 VSQSwapAmountWei = pvsqDecimals > VSQDecimals ?
                                        VSQSwapAmount / (10 ** (pvsqDecimals - VSQDecimals)) :
                                            pvsqDecimals < VSQDecimals ?
                                                VSQSwapAmount * (10 ** (VSQDecimals - pvsqDecimals)) :
                                                VSQSwapAmount;

        require(IERC20(VSQAddress).balanceOf(address(this)) >= VSQSwapAmountWei, "Not enough tokens in contract for swap");

        ERC20(preVSQ).safeTransferFrom(msg.sender, BURN_ADDRESS, VSQSwapAmount);
        ERC20(VSQAddress).safeTransfer(msg.sender, VSQSwapAmountWei);

        emit VSQSwap(msg.sender, VSQSwapAmount, VSQSwapAmountWei);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;

        emit StartBlockChanged(_newStartBlock);
    }
}