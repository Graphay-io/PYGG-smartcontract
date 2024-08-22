// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

abstract contract WhiteListManager {

    mapping(address => bool) public whitelist;
    address private owner;

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "!WHT");
        _;
    }

    constructor() {
        whitelist[msg.sender] = true;
        owner = msg.sender;
    }

    function setWhitelist(address _user, bool _status) external {
        require(msg.sender == owner, "You are not owner");
        whitelist[_user] = _status;
        // emit Whitelisted(_user, _status);
    }


}