pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// The locker stores IERC20 tokens and only allows the owner to withdraw them after the UNLOCK_BLOCKNUMBER has been reached.
contract Locker is Ownable {
    using SafeERC20 for IERC20;

    uint256 public immutable UNLOCK_BLOCKNUMBER;

    event Claim(address token, address to);

    /**
     * @notice Constructs the Locker contract.
     */
    constructor(uint256 blockNumber) public {
        require(block.number + 100 < blockNumber, "block number must be reasonably in the future");
        UNLOCK_BLOCKNUMBER = blockNumber;
    }


    /**
     * @notice claimToken allows the owner to withdraw tokens sent manually to this contract.
     * It is only callable once UNLOCK_BLOCKNUMBER has passed.
     */
    function claimToken(address token, address to) external onlyOwner {
        require(block.number > UNLOCK_BLOCKNUMBER, "still vesting...");

        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));

        emit Claim(token, to);
    }
}