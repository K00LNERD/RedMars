// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

import "./TransferHelper.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface Token {
    function decimals() external view returns (uint256);

    function symbol() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

contract Redmars is Ownable, ReentrancyGuard {
    uint256 public projectCounter; //for counting the number of project
    struct TokenSale {
        uint128 numberOfTokenForSale; //number of token user wants to sell
        uint128 priceOfTokenInBNB; // price of token set by user
        uint128 StartTime; //to mark the start of campaign
        uint128 duration; // duration of sale period
        uint128 numberOfTokenSOLD; // to track how many token got sold
        uint128 amountRaised; // to keep track of the bnb to give the user at the end of the campaign
        address tokenAddr; // token address from the campaign
        address ownerAddress; // owner of the campaign
        bool isActive; //to check if campaign is active
    }
    event invested(
        address investorAddress,
        uint256 projectID,
        uint256 amount,
        uint128 tokenSold
    );
    mapping(uint256 => TokenSale) public ProjectInfo;

    address public redmarsAddress;
    uint128 public minRedmarsAmount;

    struct UserInfo {
        uint128 tokenAmount;
        address tokenAddress;
        bool isClaimed;
    }
    mapping(address => mapping(uint256 => UserInfo)) public userInfoMapping;

    address public adminAddress;
    uint128 public adminSharePercentage; //in 10**2
    bool isInitialized;

    function initialize(
        address owner,
        address _adminAddress,
        uint128 _adminSharePercentage,
        address _redmarsAddress,
        uint128 _minRedmarsAmount
    ) public {
        require(!isInitialized, "Already initialized");
        _setOwner(owner);
        isInitialized = true;
        adminAddress = _adminAddress;
        adminSharePercentage = _adminSharePercentage;
        redmarsAddress = _redmarsAddress;
        minRedmarsAmount = _minRedmarsAmount;
    }

    function requestICO(
        uint128 _numberOfTokenForSale,
        uint128 _priceOfTokeninBNB,
        uint128 _duration,
        address _tokenAddr
    ) external nonReentrant {
        require(
            (Token(redmarsAddress).balanceOf(msg.sender)) >= minRedmarsAmount,
            "check your RedMars balance."
        );
        require(
            Token(_tokenAddr).allowance(msg.sender, address(this)) >=
                _numberOfTokenForSale,
            "Approve Tokens."
        ); // approval not given by from the token contract
        require(
            (Token(_tokenAddr).balanceOf(msg.sender)) >= _numberOfTokenForSale,
            "check your balance."
        ); //not enough token given for the campaign
        ++projectCounter;
        TokenSale memory saleInfo = TokenSale({
            numberOfTokenForSale: _numberOfTokenForSale,
            priceOfTokenInBNB: _priceOfTokeninBNB,
            StartTime: 0,
            duration: _duration,
            numberOfTokenSOLD: 0,
            amountRaised: 0,
            tokenAddr: _tokenAddr,
            ownerAddress: msg.sender,
            isActive: false
        });
        ProjectInfo[projectCounter] = saleInfo;
    }

    function approveICO(uint256 _projectId) external onlyOwner {
        // to get approval of admin
        TokenSale memory saleInfo = ProjectInfo[_projectId];
        require(
            Token(saleInfo.tokenAddr).allowance(
                saleInfo.ownerAddress,
                address(this)
            ) >= saleInfo.numberOfTokenForSale,
            "Approve Tokens."
        );
        require(
            (Token(saleInfo.tokenAddr).balanceOf(saleInfo.ownerAddress)) >=
                saleInfo.numberOfTokenForSale,
            "check your balance."
        );
        ProjectInfo[_projectId].StartTime = (uint128)(block.timestamp);
        ProjectInfo[_projectId].isActive = true;
        TransferHelper.safeTransferFrom(
            saleInfo.tokenAddr,
            saleInfo.ownerAddress,
            address(this),
            saleInfo.numberOfTokenForSale
        );
    }

    function invest(uint256 _projectId) external payable nonReentrant {
        require(msg.value > 0, "Enter valid value");
        require(
            (Token(redmarsAddress).balanceOf(msg.sender)) >= minRedmarsAmount,
            "check your RedMars balance."
        );
        TokenSale storage saleInfo = ProjectInfo[_projectId];
        require(saleInfo.isActive, "Not Active");
        uint128 tokenSold = uint128(calculateToken(_projectId, msg.value));
        require(
            (saleInfo.duration + saleInfo.StartTime > block.timestamp),
            "ICO Ended."
        );
        require(
            ((saleInfo.numberOfTokenSOLD + tokenSold) <=
                saleInfo.numberOfTokenForSale),
            "No tokens left."
        );
        UserInfo memory uInfo = UserInfo({
            tokenAmount: ((
                userInfoMapping[msg.sender][_projectId].tokenAmount
            ) + tokenSold),
            tokenAddress: saleInfo.tokenAddr,
            isClaimed: false
        });
        userInfoMapping[msg.sender][_projectId] = uInfo;
        saleInfo.numberOfTokenSOLD += tokenSold;
        saleInfo.amountRaised += uint128(msg.value);
        emit invested(msg.sender, _projectId, msg.value, tokenSold);
    }

    function calculateBNB(uint256 _projectId, uint256 _tokenAmount)
        public
        view
        returns (uint256)
    {
        TokenSale memory saleInfo = ProjectInfo[_projectId];
        return
            (_tokenAmount * saleInfo.priceOfTokenInBNB) /
            ((10**Token(saleInfo.tokenAddr).decimals())); // calculating BNB when number of token is given
    }

    function calculateToken(uint256 _projectId, uint256 _BNBAmount)
        public
        view
        returns (uint256)
    {
        TokenSale memory saleInfo = ProjectInfo[_projectId];
        return ((_BNBAmount * (10**Token(saleInfo.tokenAddr).decimals())) /
            (saleInfo.priceOfTokenInBNB)); // calculating token when number of BNB is given
    }

    function claimMoney(uint256 _projectId) external onlyOwner {
        TokenSale memory saleInfo = ProjectInfo[_projectId];
        require(saleInfo.isActive, "Not Active");
        require(
            (saleInfo.duration + saleInfo.StartTime <= block.timestamp) ||
                (saleInfo.numberOfTokenSOLD == saleInfo.numberOfTokenForSale),
            "ICO Running."
        );
        uint128 adminShare = (((saleInfo.amountRaised) * adminSharePercentage) /
            10**4); // admin's cut

        TransferHelper.safeTransferETH(
            saleInfo.ownerAddress,
            saleInfo.amountRaised - adminShare
        ); //sending BNB to campaigner
        TransferHelper.safeTransferETH(adminAddress, adminShare);
        if (saleInfo.numberOfTokenSOLD < saleInfo.numberOfTokenForSale) {
            TransferHelper.safeTransfer(
                saleInfo.tokenAddr,
                saleInfo.ownerAddress,
                ((saleInfo.numberOfTokenForSale) - (saleInfo.numberOfTokenSOLD))
            );
        }
        ProjectInfo[_projectId].isActive = false; // sending BNB to Admin
    }

    function updateRedmars(address _redmarsAddress) external onlyOwner {
        redmarsAddress = _redmarsAddress;
    }

    function updateMinRedmarsAmount(uint128 _minRedmarsAmount)
        external
        onlyOwner
    {
        minRedmarsAmount = _minRedmarsAmount;
    }

    function claimUserTokens(uint256 _projectId) external {
        TokenSale memory saleInfo = ProjectInfo[_projectId];
        require(
            (saleInfo.duration + saleInfo.StartTime <= block.timestamp) ||
                (saleInfo.numberOfTokenSOLD == saleInfo.numberOfTokenForSale),
            "ICO Running."
        );
        UserInfo storage uInfo = userInfoMapping[msg.sender][_projectId];
        require((!uInfo.isClaimed), "Already Claimed");
        TransferHelper.safeTransfer(
            saleInfo.tokenAddr,
            msg.sender,
            uInfo.tokenAmount
        );
        uInfo.isClaimed = true;
    }

    function updateAdminAddress(address _adminAddress) external onlyOwner {
        adminAddress = _adminAddress;
    }

    function updateAdminSharePercentage(uint128 _adminSharePercentage)
        external
        onlyOwner
    {
        adminSharePercentage = _adminSharePercentage;
    }
}
