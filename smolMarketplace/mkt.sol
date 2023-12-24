// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/IERC721.sol";
import "../utils/IERC20.sol";

contract NFTDepositContract {

    // Collection + tokenId are used as unique identifiers for each NFT struct.
    struct NFTDeposit {
        address depositor;
        address collection;
        uint256 tokenId;
        uint256 minimumPrice;
        bool forSale;
        address[] bidders;
    }

    struct Bid {
        address bidder;
        uint256 bidId;
        uint256 amount;
        uint256 deadline;
    }

    mapping(address => mapping(uint256 => NFTDeposit)) public tokenDeposits;
    mapping(bytes32 => uint256) private bidIdMapping;
    mapping(uint256 => Bid) public bids;

    // Optional smolMarketplace fees
    uint256 public mktFee = 5;

    uint256 private bidId;
    address private WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /*
    ##############################
          Deposit / Withdraw       
    ##############################
    */

    function depositNFT(address _collection, uint256 _tokenId) public {
        IERC721 nft = IERC721(_collection);
        require(nft.ownerOf(_tokenId) == msg.sender, "You are not the owner");

        nft.transferFrom(msg.sender, address(this), _tokenId);

        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];

        nftData.depositor = msg.sender;
        nftData.collection = _collection;
        nftData.tokenId = _tokenId;
        nftData.minimumPrice = 0; // Set the default value or update as needed
        nftData.forSale = false; // Set the default value or update as needed

    }   

    function withdrawNFT(address _collection, uint256 _tokenId) public {
        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];
        require(nftData.depositor == msg.sender, "You are not the owner");

        IERC721 nft = IERC721(_collection);

        nft.transferFrom(address(this), msg.sender, _tokenId);
        delete nftData;
    }

    /*
    ##############################
                Listings      
    ##############################
    */

    function listNFT(address _collection, uint256 _tokenId, uint256 _price) public {
        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];
        require(nftData.depositor == msg.sender);

        nftData.forSale = true;
        nftData.minimumPrice = _price;
    }

    function unlistNFT(address _collection, uint256 _tokenId) public {
        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];
        require(nftData.depositor == msg.sender);
        
        nftData.forSale = false;
        nftData.minimumPrice = 0;

        delete nftData;
    }

    /*
    ##############################
               Buy / Bid      
    ##############################
    */

    function buyNFT(address _collection, uint256 _tokenId) public {
        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];
        require(nftData.forSale, "Not for sale");
        
        uint256 fee = (nftData.minimumPrice * mktFee) / 100;
        IERC20(WETH).transferFrom(msg.sender, nftData.depositor, nftData.minimumPrice - fee);

        IERC721 nft = IERC721(_collection);
        nft.transferFrom(address(this), msg.sender, _tokenId);

        delete nftData;
    }

    function placeBid(address _collection, uint256 _tokenId, uint256 _amount, uint256 _deadline) public {
        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];
        require(nftData.forSale, "Not for sale");
        require(block.timestamp < bid.deadline, "Deadline must be greater that current time");

        IERC20(WETH).transferFrom(msg.sender, address(this), _amount);

        bytes32 bidKey = _getBidKey(msg.sender, collection, tokenId);
        uint256 bidId = bidIdMapping[bidKey];

        bids[bidId] = Bid({
            bidId: bidId,
            amount: _amount,
            deadline: _deadline
        });

        nftDeposit.bidders.push(msg.sender);
        bidId += 1;
    }

    function removeBid(address _collection, uint256 _tokenId) public {
        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];
        require(nftData.bids[msg.sender].amount > 0, "No bids available");

        bytes32 bidKey = _getBidKey(msg.sender, collection, tokenId);
        uint256 bidId = bidIdMapping[bidKey];

        require(bidId != 0, "No active bid found");
        Bid storage bid = bids[bidId];
        require(bid.bidder == msg.sender, "Not the bidder");

        IERC20(WETH).transfer(msg.sender, nftData.bids[msg.sender].amount);
        delete bids[bidId];
        delete bidIdMapping[bidKey];
    }

    function acceptBid(address _collection, uint256 _tokenId, address _bidder) public {
        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];
        require(block.timestamp < bid.deadline, "Bid expired");
        require(nftData.depositor == msg.sender, "You are not the owner");

        bytes32 bidKey = _getBidKey(_bidder, collection, tokenId);
        uint256 bidId = bidIdMapping[bidKey];

        Bid storage bid = bids[bidId];

        IERC20(WETH).transfer(nftData.depositor, bid.amount);

        IERC721 nft = IERC721(_collection);
        nft.transferFrom(address(this), _bidder, _tokenId);

        delete bids[bidId];
        delete bidIdMapping[bidKey];
    }

    /*
    ##############################
            Info Retrieval      
    ##############################
    */

    function getNFTPrice(address _collection, uint256 _tokenId) public view returns(uint256) {
        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];
        require(nftData.forSale, "NFT is not for sale");

        return nftData.minimumPrice;
    }

    function isForSale(address _collection, uint256 _tokenId) public view returns(bool) {
        NFTDeposit storage nftData = tokenDeposits[_collection][_tokenId];

        return nftData.forSale;
    }

    function getBidsForNFT(address collection, uint256 tokenId) public view returns (Bid[] memory) {
        NFTDeposit storage nftDeposit = tokenDeposits[collection][tokenId];
        Bid[] memory nftBids = new Bid[](nftDeposit.bidders.length);

        for (uint i = 0; i < nftDeposit.bidders.length; i++) {
            bytes32 bidKey = keccak256(abi.encodePacked(nftDeposit.bidders[i], collection, tokenId));
            uint256 bidId = bidIdMapping[bidKey];
            nftBids[i] = bids[bidId];
        }

        return nftBids;
    }

    // Generate a key that associates a bidder with a bidId
    function _getBidKey(address bidder, address collection, uint256 tokenId) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(bidder, collection, tokenId));
    }
}