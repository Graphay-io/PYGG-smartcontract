// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract WhiteListManager {

    mapping(address => bool) public whitelist;
    address[] private whitelistedAddresses;
    address private owner;
    event Whitelisted(address indexed user, bool isWhitelisted);


    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "!WHT");
        _;
    }

    constructor(address _owner) {
        whitelist[msg.sender] = true;
        whitelistedAddresses.push(msg.sender); // Add the contract deployer to the whitelist
        owner = _owner;
    }

    function setWhitelist(address _user, bool _status) external {
        require(msg.sender == owner, "You are not owner");

        if (_status && !whitelist[_user]) {
            // Add to whitelist and track address
            whitelist[_user] = true;
            whitelistedAddresses.push(_user);
        } else if (!_status && whitelist[_user]) {
            // Remove from whitelist but keep address in array (optional)
            whitelist[_user] = false;
        }
        emit Whitelisted(_user, _status);
    }

    function getWhitelistedUsers() external view returns (address[] memory) {
        uint256 count = 0;

        // Count the number of currently whitelisted users
        for (uint256 i = 0; i < whitelistedAddresses.length; i++) {
            if (whitelist[whitelistedAddresses[i]]) {
                count++;
            }
        }

        address[] memory activeWhitelisted = new address[](count);
        uint256 index = 0;

        // Populate the array with active whitelisted users
        for (uint256 i = 0; i < whitelistedAddresses.length; i++) {
            if (whitelist[whitelistedAddresses[i]]) {
                activeWhitelisted[index] = whitelistedAddresses[i];
                index++;
            }
        }

        return activeWhitelisted;
    }
}
