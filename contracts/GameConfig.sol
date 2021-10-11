// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import './modules/Initializable.sol';

contract GameConfig is Initializable {
    address public owner;
    address public dev;
    address public admin;
    address public team;
    address public uploader;

    event OwnerChanged(address indexed _user, address indexed _old, address indexed _new);
    event DevChanged(address indexed _user, address indexed _old, address indexed _new);
    event AdminChanged(address indexed _user, address indexed _old, address indexed _new);
    event TeamChanged(address indexed _user, address indexed _old, address indexed _new);
    event UploaderChanged(address indexed _user, address indexed _old, address indexed _new);

    function initialize() external initializer {
        owner = msg.sender;
        dev = msg.sender;
        admin = msg.sender;
        team = msg.sender;
        uploader = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, 'GameConfig: Only Owner');
        _;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin || msg.sender == owner, "GameConfig: FORBIDDEN");
        _;
    }
    
    modifier onlyDev() {
        require(msg.sender == dev || msg.sender == owner, "GameConfig: FORBIDDEN");
        _;
    }
        
    modifier onlyTeam() {
        require(msg.sender == team || msg.sender == owner, "GameConfig: FORBIDDEN");
        _;
    }
            
    modifier onlyUploader() {
        require(msg.sender == uploader || msg.sender == owner, "GameConfig: FORBIDDEN");
        _;
    }

    function changeOwner(address _user) external onlyOwner {
        require(owner != _user, 'GameConfig: NO CHANGE');
        emit OwnerChanged(msg.sender, owner, _user);
        owner = _user;
    }

    function changeDev(address _user) external onlyDev {
        require(dev != _user, 'GameConfig: NO CHANGE');
        emit DevChanged(msg.sender, dev, _user);
        dev = _user;
    }

    function changeAdmin(address _user) external onlyAdmin {
        require(admin != _user, 'GameConfig: NO CHANGE');
        emit AdminChanged(msg.sender, admin, _user);
        admin = _user;
    }

    function changeTeam(address _user) external onlyTeam {
        require(team != _user, 'GameConfig: NO CHANGE');
        emit TeamChanged(msg.sender, team, _user);
        team = _user;
    }

    function changeUploader(address _user) external onlyUploader {
        require(uploader != _user, 'GameConfig: NO CHANGE');
        emit UploaderChanged(msg.sender, uploader, _user);
        uploader = _user;
    }
}