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
    mapping(address => uint256) pendingReturns;
    uint256 totalPendingReturns = 0;

    bool ended;

    // Events that will be emitted on changes.
    event HighestBidIncreased(address bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);

    // Errors
    error AuctionSlotUsed();
    error AuctionHasNotStarted();
    error AuctionAlreadyEnded();
    error BidNotHighEnough();
    error AuctionNotYetEnded();

    function auctionStart(
        uint256 biddingTime,
        address _tokenAddress,
        uint256 _tokenId
    ) external onlyOwner {
        // one time only
        if (auctionEndTime != 0) revert AuctionSlotUsed();

        auctionEndTime = block.timestamp + biddingTime;

        tokenInterface = IERC721Lite(_tokenAddress);
        tokenId = _tokenId;

        tokenInterface.safeTransferFrom(msg.sender, address(this), _tokenId);
    }

    function bid() external payable {
        if (auctionEndTime == 0) revert AuctionHasNotStarted();
        if (block.timestamp >= auctionEndTime) revert AuctionAlreadyEnded();
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

            if (!payable(msg.sender).send(amount)) {
                pendingReturns[msg.sender] = amount;
            } else {
                totalPendingReturns -= amount;
            }
        }

        emit HighestBidIncreased(msg.sender, msg.value);
    }

    function hasBid() external view returns (bool) {
        return pendingReturns[msg.sender] != 0;
    }

    function withdraw() external {
        if (auctionEndTime == 0) revert AuctionHasNotStarted();

        uint256 amount = pendingReturns[msg.sender];
        if (amount != 0) {
            pendingReturns[msg.sender] = 0;

            if (!payable(msg.sender).send(amount)) {
                pendingReturns[msg.sender] = amount;
            } else {
                totalPendingReturns -= amount;
            }
        }
    }

    function auctionEnd() external {
        if (auctionEndTime == 0) revert AuctionHasNotStarted();
        if (block.timestamp <= auctionEndTime) revert AuctionNotYetEnded();
        if (ended) revert AuctionAlreadyEnded();

        ended = true;
        emit AuctionEnded(highestBidder, highestBid);

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
