// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "ds-test/test.sol";

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "./ERC721Mock.sol";
import "../Auction.sol";

interface HEVM {
    function warp(uint256 time) external;

    function prank(
        address,
        address,
        bytes calldata
    ) external payable returns (bool, bytes memory);

    function deal(address, uint256) external;

    function expectRevert(bytes calldata) external;
}

contract ContractTest is DSTest, ERC721Holder {
    HEVM private hevm = HEVM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    ERC721Mock private MOCK_TOKEN;
    Auction private AUCTION_CONTRACT;
    address private owner;
    address private other = address(0xdeadbeef);

    uint256 private tokenId = 0;

    function setUp() public {
        MOCK_TOKEN = new ERC721Mock("Mock", "MOCK");
        AUCTION_CONTRACT = new Auction();
        owner = address(this);

        MOCK_TOKEN.mint(tokenId);
        MOCK_TOKEN.mint(tokenId + 1);
        MOCK_TOKEN.approve(address(AUCTION_CONTRACT), tokenId);
        MOCK_TOKEN.approve(address(AUCTION_CONTRACT), tokenId + 1);
    }

    function otherPersonBid(uint256 amount) public {
        bytes memory calld = abi.encodePacked(
            AUCTION_CONTRACT.bid.selector,
            abi.encode()
        );
        calld = abi.encodePacked(
            hevm.prank.selector,
            abi.encode(other, address(AUCTION_CONTRACT), calld)
        );
        (bool success, bytes memory _res) = address(hevm).call{value: amount}( // solhint-disable-line
            calld
        );
        assertTrue(success);
    }

    function testSimple() public {
        // Starting auction with tokenTransfer
        assertTrue(owner == MOCK_TOKEN.ownerOf(tokenId));
        AUCTION_CONTRACT.auctionStart(1 days, address(MOCK_TOKEN), tokenId);
        assertTrue(address(AUCTION_CONTRACT) == MOCK_TOKEN.ownerOf(tokenId));

        AUCTION_CONTRACT.bid{value: 1 ether}();

        // User gets his past overbid amount if he bids again
        hevm.deal(other, 10 ether);
        otherPersonBid(2 ether);
        assert(address(other).balance == 8 ether);
        otherPersonBid(3 ether);
        assert(address(other).balance == 7 ether);

        // Overbid return
        assertTrue(AUCTION_CONTRACT.hasBid());
        uint256 prevAmount = address(owner).balance;
        AUCTION_CONTRACT.withdraw();
        assertTrue(address(owner).balance == prevAmount + 1 ether);

        // End Auction and Giveaway
        hevm.warp(2 days);
        AUCTION_CONTRACT.auctionEnd();
        assertTrue(other == MOCK_TOKEN.ownerOf(tokenId));

        // Collect HighestBid
        prevAmount = address(owner).balance;
        AUCTION_CONTRACT.withdrawHighestBid();
        assertTrue(address(owner).balance == prevAmount + 3 ether);
    }

    function testErrors() public {
        AUCTION_CONTRACT.auctionStart(1 days, address(MOCK_TOKEN), tokenId);

        // --
        hevm.expectRevert(
            abi.encodePacked(bytes4(keccak256("AuctionSlotUsed()")))
        );
        AUCTION_CONTRACT.auctionStart(1 days, address(MOCK_TOKEN), tokenId + 1);

        // --
        hevm.expectRevert(
            abi.encodePacked(bytes4(keccak256("AuctionNotYetEnded()")))
        );
        AUCTION_CONTRACT.withdrawHighestBid();

        // --
        AUCTION_CONTRACT.bid{value: 1 ether}();
        hevm.expectRevert(
            abi.encodePacked(bytes4(keccak256("BidNotHighEnough()")))
        );
        AUCTION_CONTRACT.bid{value: 0.5 ether}();

        // --
        hevm.warp(2 days);
        hevm.expectRevert(
            abi.encodePacked(bytes4(keccak256("AuctionAlreadyEnded()")))
        );
        AUCTION_CONTRACT.bid{value: 2 ether}();
    }

    receive() external payable {} // solhint-disable-line

    fallback() external payable {} // solhint-disable-line
}
