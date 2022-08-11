// SPDX-License-Identifier: MIT
pragma solidity >=0.8.14;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract dCheque is ERC721, Ownable {
    struct Cheque{
        uint256 amount;
        uint256 created;
        uint256 expiry;
        IERC20 token;
        address drawer;
        address recipient;
        address auditor;
    }
    /*//////////////////////////////////////////////////////////////
                           STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address=>mapping(address=>bool)) public userAuditor;  // Whether User accepts Auditor
    mapping(address=>mapping(address=>bool)) public auditorUser;  // Whether Auditor accepts User
    mapping(address=>mapping(uint256=>bool)) public auditorDurations;  // Auditor voiding periods
    mapping(address=>address[]) public acceptedUserAuditors;  // Auditor addresses that user accepts
    mapping(address=>address[]) public acceptedAuditorUsers;  // User addresses that auditor accepts

    mapping(address=>address) public trustedAccount;  // User's trusted account
    mapping(address=>uint256) public lastTrustedChange;  // Last time user updated changed account
    uint256 public trustedAccountCooldown;  // Cooldown before user can change trusted account again

    mapping(uint256=>Cheque) public chequeInfo;  // Cheque information
    mapping(address=>mapping(IERC20=>uint256)) public deposits;  // Total user deposits
    uint256 private totalSupply;  // Total cheques created

    mapping(IERC20=>uint256) public protocolFee;  // Fee in ERC20 token taken from each cheque transfer
    mapping(IERC20=>uint256) public protocolReserve;  // Token balances not needed for cheque collateralization
    /*//////////////////////////////////////////////////////////////
                           EVENTS/MODIFIERS
    //////////////////////////////////////////////////////////////*/
    event Deposit(IERC20 _token, address indexed to, uint256 amount);
    event Cash(address indexed bearer, uint256 indexed chequeID);
    event Void(address indexed drawer, address indexed auditor, uint256 indexed chequeID);
    
    event AcceptAuditor(address indexed user, address indexed auditor);
    event AcceptUser(address indexed auditor, address indexed user);
    
    event SetProtocolFee(IERC20 _token, uint256 amount);
    event Withdraw(address indexed _address, uint256 amount);

    modifier UserAuditorUserHandshake(IERC20 _token, uint256 amount, address auditor, uint256 duration, address recipient){
        require(deposits[_msgSender()][_token]>=amount, "Insufficient balance");
        require(userAuditor[_msgSender()][auditor], "Unapproved auditor");
        require(auditorUser[auditor][_msgSender()],  "Auditor must approve you");
        require(auditorUser[auditor][recipient],  "Auditor must approve recipient");
        require(userAuditor[recipient][auditor], "Recipient must approve auditor");
        require(auditorDurations[auditor][duration], "Duration not allowed");
        _;
    }
    /*//////////////////////////////////////////////////////////////
                        ONLY OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(uint256 _trustedAccountCooldown) ERC721("dCheque", "dCHQ"){
        trustedAccountCooldown = _trustedAccountCooldown;
    }
    function setProtocolFee(IERC20 _token, uint256 _protocolFee) external onlyOwner{  
        protocolFee[_token] = _protocolFee;
        emit SetProtocolFee(_token, _protocolFee);
    }
    function withdraw(IERC20 _token, uint256 _amount) external onlyOwner{
        require(protocolReserve[_token]>=_amount, "More than available");
        protocolReserve[_token]-= _amount;
        bool success = _token.transferFrom(address(this), _msgSender(), _amount);
        require(success, "Transfer failed.");
        emit Withdraw(_msgSender(), _amount);
    }
    /*//////////////////////////////////////////////////////////////
                            USER DEPOSITS
    //////////////////////////////////////////////////////////////*/
    function _deposit(IERC20 _token, address _address, uint256 _amount) private {
        bool success = _token.transferFrom(_msgSender(), address(this), _amount); 
        require(success, "Transfer failed");
        deposits[_address][_token] += _amount;
        emit Deposit(_token, _address, _amount);
    }
    function deposit(IERC20 _token, uint256 _amount) external returns (bool){
        _deposit(_token, _msgSender(), _amount);
        return true;
    }
    function deposit(IERC20 _token, uint256 _amount, address _address) external returns (bool){
        _deposit(_token, _address, _amount);
        return true;
    }
    function directTransfer(IERC20 _token, address _to, uint256 _amount) external{
        uint256 fromBalance = deposits[_msgSender()][_token];
        require(fromBalance >= _amount, "transfer amount exceeds balance");
        unchecked {deposits[_msgSender()][_token] = fromBalance - _amount;}
        deposits[_to][_token] += _amount;
    }
    /*//////////////////////////////////////////////////////////////
                          ERC-721 OVERRIDES
    //////////////////////////////////////////////////////////////*/
    function _feeOnTransfer(uint256 chequeID) private{
        Cheque storage cheque = chequeInfo[chequeID];
        IERC20 _token = cheque.token;
        require(cheque.amount >= protocolFee[_token]);
        unchecked {cheque.amount = cheque.amount  - protocolFee[_token];}
        protocolReserve[_token] += protocolFee[_token];
    }
    function transferFrom(address from, address to, uint256 chequeID) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), chequeID), "Transfer disallowed");
        _feeOnTransfer(chequeID);
        _transfer(from, to, chequeID);
    }
    function safeTransferFrom(address from, address to, uint256 chequeID, bytes memory data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), chequeID), "Transfer disallowed");
        _feeOnTransfer(chequeID);
        _safeTransfer(from, to, chequeID, data);
    }
    /*//////////////////////////////////////////////////////////////
                        ERC-721 FUNCTION USAGE
    //////////////////////////////////////////////////////////////*/
    function writeCheque(IERC20 _token, uint256 amount, uint256 duration, address auditor, address recipient) 
        external 
        UserAuditorUserHandshake(_token, amount, auditor, duration, recipient) {
        deposits[_msgSender()][_token] -= amount;
        _safeMint(_msgSender(), totalSupply);
        chequeInfo[totalSupply] = Cheque({drawer:_msgSender(), recipient:recipient, created:block.timestamp, expiry:block.timestamp+duration, 
                                       auditor:auditor, token:_token, amount:amount});
        totalSupply += 1;
    }
    function cashCheque(uint256 chequeID) external {
        Cheque storage cheque = chequeInfo[chequeID];
        require(_isApprovedOrOwner(_msgSender(), chequeID), "Must own cheque");
        require(cheque.expiry>block.timestamp, "Cashable yet");
        bool success = cheque.token.transferFrom(address(this), _msgSender(), cheque.amount);
        require(success, "Transfer failed.");
        _burn(chequeID); 
        emit Cash(_msgSender(), chequeID);
    }
    function _voidCheque(uint256 chequeID, address depositTo) private {
        Cheque memory cheque = chequeInfo[chequeID];
        require(cheque.auditor==_msgSender(), "Not auditor");
        require(cheque.expiry<block.timestamp, "Cheque matured");
        _burn(chequeID); 
        deposits[depositTo][cheque.token] += cheque.amount;  // Add balance back to drawer
        emit Void(cheque.drawer, cheque.auditor, chequeID);
    }
    function voidCheque(uint256 chequeID) external {
        _voidCheque(chequeID, _msgSender());
    }
    function voidRescueCheque(uint256 chequeID) external {
        _voidCheque(chequeID, trustedAccount[chequeInfo[chequeID].drawer]);
    }
    /*//////////////////////////////////////////////////////////////
                          AUDITOR FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function acceptAuditor(address auditor) external returns (bool){  // User will set this 
        if (userAuditor[_msgSender()][auditor]){
            return true;
        }
        userAuditor[_msgSender()][auditor] = true;
        if (auditorUser[auditor][_msgSender()]){
            acceptedAuditorUsers[auditor].push(_msgSender());
            acceptedUserAuditors[_msgSender()].push(auditor);
        }
        emit AcceptAuditor(_msgSender(), auditor);
        return true;
    }
    function acceptUser(address drawer) external returns (bool){  // Auditor will set this 
        if (auditorUser[_msgSender()][drawer]){
            return true;
        }
        auditorUser[_msgSender()][drawer] = true;
        if (userAuditor[drawer][_msgSender()]){
            acceptedUserAuditors[drawer].push(_msgSender());
            acceptedAuditorUsers[_msgSender()].push(drawer);
        }
        emit AcceptUser(_msgSender(), drawer);
        return true;
    }
    function setAllowedDuration(uint256 duration) external {  // Auditor will set this
        auditorDurations[_msgSender()][duration] = true;
    }
    function getAcceptedUserAuditors(address _address) external view returns (address[] memory){
        return acceptedUserAuditors[_address];
    }
    function getAcceptedAuditorUsers(address _address) external view returns (address[] memory){
        return acceptedAuditorUsers[_address];
    }
    function setTrustedAccount(address account) external {  // User will set this
        require((lastTrustedChange[_msgSender()] + trustedAccountCooldown)<block.timestamp, "Trusted account cooldown");
        trustedAccount[_msgSender()] = account;
        lastTrustedChange[_msgSender()] = block.timestamp;
    }
    /*//////////////////////////////////////////////////////////////
                         CHEQUE READ FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function chequeDrawer(uint256 chequeId) external view returns (address) {
        return chequeInfo[chequeId].drawer;
    }
    function chequeRecipient(uint256 chequeId) external view returns (address) {
        return chequeInfo[chequeId].recipient;
    }
    function chequeAuditor(uint256 chequeId) external view returns (address) {
        return chequeInfo[chequeId].auditor;
    } 
    function chequeAmount(uint256 chequeId) external view returns (uint256) {
        return chequeInfo[chequeId].amount;
    }
    function chequeExpiry(uint256 chequeId) external view returns (uint256) {
        return chequeInfo[chequeId].expiry;
    }
    function chequeCreated(uint256 chequeId) external view returns (uint256) {
        return chequeInfo[chequeId].created;
    }
}