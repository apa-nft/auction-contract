// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

interface IERC721Lite {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

contract Auction is Ownable, ERC721Holder {
    IERC721Lite public tokenInterface;
    uint256 public tokenId;
    uint256 public auctionEndTime;

    // Current state of the auction.
    address public highestBidder;
    uint256 public highestBid;

    // Allowed withdrawals of previous bids
    mapping(address => uint256) private pendingReturns;
    uint256 private totalPendingReturns = 0;

    bool public ended;

    // Errors
    error AuctionSlotUsed();
    error AuctionHasNotStarted();
    error AuctionAlreadyEnded();
    error BidNotHighEnough();
    error AuctionNotYetEnded();
    error TransferFailed();

    function auctionStart(
        uint256 biddingTime,
        address _tokenAddress,
        uint256 _tokenId
    ) external onlyOwner {
        // one time only
        if (auctionEndTime != 0) revert AuctionSlotUsed();

        auctionEndTime = block.timestamp + biddingTime; // solhint-disable-line

        tokenInterface = IERC721Lite(_tokenAddress);
        tokenId = _tokenId;

        tokenInterface.safeTransferFrom(msg.sender, address(this), _tokenId);
    }

    function bid() external payable {
        if (!(auctionEndTime != 0)) revert AuctionHasNotStarted();
        if (block.timestamp >= auctionEndTime) revert AuctionAlreadyEnded(); // solhint-disable-line
        if (msg.value <= highestBid) revert BidNotHighEnough();

        if (highestBid != 0) {
            pendingReturns[highestBidder] += highestBid;
            totalPendingReturns += highestBid;
        }

        highestBidder = msg.sender;
        highestBid = msg.value;

        // withdraw previous bid
        uint256 amount = pendingReturns[msg.sender];

        if (amount != 0) {
            pendingReturns[msg.sender] = 0;
            totalPendingReturns -= amount;

            //slither-disable-next-line low-level-calls
            (bool success, ) = msg.sender.call{value: amount}(""); // solhint-disable-line
            if (!success) revert TransferFailed();
        }
    }

    function hasBid() external view returns (bool) {
        return pendingReturns[msg.sender] != 0;
    }

    function withdraw() external {
        if (!(auctionEndTime != 0)) revert AuctionHasNotStarted();

        uint256 amount = pendingReturns[msg.sender];
        if (amount != 0) {
            pendingReturns[msg.sender] = 0;
            totalPendingReturns -= amount;

            //slither-disable-next-line low-level-calls
            (bool success, ) = msg.sender.call{value: amount}(""); // solhint-disable-line
            if (!success) revert TransferFailed();
        }
    }

    function auctionEnd() external {
        if (!(auctionEndTime != 0)) revert AuctionHasNotStarted();
        if (block.timestamp <= auctionEndTime) revert AuctionNotYetEnded(); // solhint-disable-line
        if (ended) revert AuctionAlreadyEnded();

        ended = true;

        tokenInterface.safeTransferFrom(address(this), highestBidder, tokenId);
    }

    function withdrawHighestBid() external onlyOwner {
        if (!ended) revert AuctionNotYetEnded();

        payable(msg.sender).transfer(highestBid);
    }

    function withdrawEmergency() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
