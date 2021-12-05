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

    function auctionStart(uint256 biddingTime, address _tokenAddress, uint256 _tokenId) external onlyOwner {
        // one time only
        require(auctionEndTime == 0);

        auctionEndTime = block.timestamp + biddingTime;

        tokenInterface = IERC721Lite(_tokenAddress);
        tokenId = _tokenId;

        tokenInterface.safeTransferFrom(_msgSender(), address(this), _tokenId);
    }

    function bid() external payable {

        require(auctionEndTime != 0, "AuctionHasNotStarted");
        require(block.timestamp < auctionEndTime, "AuctionAlreadyEnded");
        require(msg.value > highestBid, "BidNotHighEnough");

        if (highestBid != 0) {
            pendingReturns[highestBidder] += highestBid;
            totalPendingReturns += highestBid;
        }

        highestBidder = _msgSender();
        highestBid = msg.value;

        // withdraw previous bid
        uint256 amount = pendingReturns[_msgSender()];
        if(amount > 0) {
            pendingReturns[_msgSender()] = 0;

            if (!payable(_msgSender()).send(amount)) {
                pendingReturns[_msgSender()] = amount;
            }
            else {
                totalPendingReturns -= amount;
            }
        }

        emit HighestBidIncreased(_msgSender(), msg.value);
    }

    function hasBid() external view returns (bool) {
        return pendingReturns[_msgSender()] > 0;
    }

    function withdraw() external {
        require(auctionEndTime != 0, "AuctionHasNotStarted");

        uint256 amount = pendingReturns[_msgSender()];
        if (amount > 0) {
            pendingReturns[_msgSender()] = 0;

            if (!payable(_msgSender()).send(amount)) {
                pendingReturns[_msgSender()] = amount;
            }
            else {
                totalPendingReturns -= amount;
            }
        }
    }

    function auctionEnd() external {

        require(auctionEndTime != 0, "AuctionHasNotStarted");
        require(block.timestamp > auctionEndTime, "AuctionNotYetEnded");
        require(!ended, "AuctionEndAlreadyCalled");

        ended = true;
        emit AuctionEnded(highestBidder, highestBid);

        tokenInterface.safeTransferFrom(address(this), highestBidder, tokenId);
    }

    function withdrawHighestBid() external onlyOwner {
        require(ended, "AuctionNotYetEnded");

        payable(_msgSender()).transfer(highestBid);
    }

    function withdrawEmergency() external onlyOwner {
        payable(_msgSender()).transfer(address(this).balance);
    }
}