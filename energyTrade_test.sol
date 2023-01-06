pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

contract energyTrade{
    struct User {
        address addr;
        string userName;
    }
    User[] users;
    mapping (address => string) name;  // the same as User.userName
    mapping (address => int) identity; // 0:power grid, 1:PV, 2:energy storage, 3:charging station
    mapping (address => uint) balance; // 记录余额
    
    struct Sell {
        address seller;
        int amount;
        int price;
    }
    Sell[] sell;
    Sell[] sell2; // a backup for "sell" in marketOrder

    struct Buy {
        address buyer;
        int amount;
        int price;
    }
    Buy[] buy;
    Buy[] buy2;
    
    // "transaction" records all data generated from historical transactions
    struct Transaction {
        address seller;
        address buyer;
        int amount;
        int price;
        int time;
    }
    Transaction[] transaction;

    function() public payable {}

    /* basic functions */
    function createAccount(string _userName, int _userType) public returns(string memory) {
        for (uint i = 0; i < users.length; ++i) {
            if (users[i].addr == msg.sender)
                return ("You already have an account!");
            if (keccak256(users[i].userName) == keccak256(_userName))
                return ("Name already used.");
        }

        users.push(User(msg.sender, _userName));
        name[msg.sender] = _userName;
        identity[msg.sender] = _userType;
        balance[msg.sender] = 0; // 注册时余额初始值为 0

        return ("Registration successful!");
    }

    /* P2P Transaction */
    function limitOrder(int _price, int _amount, int _kind) public {
        require (_kind == 0 || _kind == 1); // 0:seller, 1:buyer
        if (_kind == 0){
            // append the limit order to the database
            sell.push(Sell(msg.sender, _amount, _price));

            // sort the orders according to their price (with the highest at the end)
            // first compare the newly-arrived order and the last but one sorted order
            if (sell.length > 1 && (_price < sell[(sell.length)-2].price)) { // the method remains to be optimized
                for (uint i = 0; i < sell.length; ++i) {
                    if (_price <= sell[i].price) {
                        for (uint j = (sell.length)-1; j > i; --j) {
                            sell[j] = sell[j-1];
                        }
                        sell[i].seller = msg.sender;
                        sell[i].amount = _amount;
                        sell[i].price = _price;
                        break;
                    }
                }
            }
        }

        if (_kind == 1){
            buy.push(Buy(msg.sender, _amount, _price));

            // sort the orders so that the one with the lowest bid is at the end
            if (buy.length > 1 && (_price > buy[(buy.length)-2].price)) {
                for (uint k = 0; k < buy.length; ++k) {
                    if (_price >= buy[k].price) {
                        for (uint l = (buy.length)-1; l > k; --l) {
                            buy[l] = buy[l-1];
                        }
                        buy[k].buyer = msg.sender;
                        buy[k].amount = _amount;
                        buy[k].price = _price;
                        break;
                    }
                }
            }
        }
    }
    
    function marketOrder(int _amount, int _kind) public returns(string memory, int) {
        require (_kind == 0 || _kind == 1); // 0:seller, 1:buyer
        int remainingAmount = _amount;
        int settlePoint; // the limit order index at which the market order is satisfied
        if (_kind == 0) {
            if (buy.length == 0) return ("There is no buyer yet. Remaining amount:", _amount);
            else {
                for (uint i = 0; i < buy.length; ++i) { // start matching with the highest bid
                    remainingAmount -= int(buy[i].amount);
                    int realAmount; // the real trading amount
                    if (remainingAmount <= 0) { // the seller has already been satisfied
                        settlePoint = int(i);
                        realAmount = buy[i].amount + remainingAmount;
                    }
                    else {
                        realAmount = buy[i].amount;
                    }
                    transaction.push(Transaction(msg.sender, buy[i].buyer, realAmount, buy[i].price, int(now)));

                    if (remainingAmount <= 0) break;
                }

                if (remainingAmount > 0) {
                    delete buy;
                    return ("The buyer amount is not enough now. Remaining amount:", remainingAmount);
                }
                else {
                    if (remainingAmount == 0) {
                        for (uint j = uint(settlePoint) + 1; j < buy.length; ++j)
                            buy2.push(buy[j]);
                    }
                    else {
                        for (uint k = uint(settlePoint); k < buy.length; ++k)
                            buy2.push(buy[k]);
                        buy2[0].amount = -remainingAmount;
                    }
                    delete buy;
                    buy = buy2;
                    delete buy2;
                    return ("Transaction complete. Remaining amount:", 0);
                }
            }
        }

        if (_kind == 1){
            if (sell.length == 0) return ("There is no seller yet. Remaining amount:", _amount);
            else {
                for (uint l = 0; l < sell.length; l++) { // start matching with the lowest offer
                    remainingAmount -= sell[l].amount;
                    int mm; // the real trading amount
                    if (remainingAmount <= 0) { // the buyer is satisfied
                        settlePoint = int(l);
                        mm = sell[l].amount + remainingAmount;
                    }
                    else {
                        mm = sell[l].amount;
                    }
                    transaction.push(Transaction(sell[l].seller, msg.sender, mm, sell[l].price, int(now)));

                    if (remainingAmount <= 0) break;
                }

                if (remainingAmount > 0) {
                    delete sell;
                    return ("The seller amount is not enough now. Remaining amount:", remainingAmount);
                }
                else {
                    if (remainingAmount == 0) {
                        for (uint m = uint(settlePoint) + 1; m < sell.length; ++m)
                            sell2.push(sell[m]);
                    }
                    else{
                        for (uint n = uint(settlePoint); n < sell.length; ++n)
                            sell2.push(sell[n]);
                        sell2[0].amount = -remainingAmount;
                    }
                    delete sell;
                    sell = sell2;
                    delete sell2;
                    return ("Transaction complete. Remaining amount:", 0);
                }
            }
        }
    }

    function enterNextPeriod() public {
        delete buy;
        delete sell;
    }
    
    /* display module */
    function getName(address _userAddr) public view returns(string memory, int) {
        for (uint i = 0; i < users.length; ++i) {
            if (users[i].addr == _userAddr)
                return (name[_userAddr], identity[_userAddr]);
        }

        return ("User not registered.", 3);
    }
    
    // show transaction history
    function auctionInquiry() public view returns(string[] memory, string[] memory, int[] memory, int[] memory, int[] memory) {
        uint len;
        if (transaction.length >= 50) len = 50;
        else len = transaction.length;
        string[] memory sellerName = new string[](len);
        string[] memory buyerName = new string[](len);
        int[] memory sellingPrice = new int[](len);
        int[] memory sellingAmount = new int[](len);
        int[] memory sellingTime = new int[](len);

        if (transaction.length >= 50) {
            for (uint i = transaction.length - 50; i < transaction.length; ++i) {
                sellerName[i] = name[transaction[i].seller];
                buyerName[i] = name[transaction[i].buyer];
                sellingPrice[i] = transaction[i].price;
                sellingAmount[i] = transaction[i].amount;
                sellingTime[i] = transaction[i].time;
            }
        }
        else {
            for (uint j = 0; j < len; ++j) {
                sellerName[j] = name[transaction[j].seller];
                buyerName[j] = name[transaction[j].buyer];
                sellingPrice[j] = transaction[j].price;
                sellingAmount[j] = transaction[j].amount;
                sellingTime[j] = transaction[j].time;
            }
        }

        return (sellerName, buyerName, sellingPrice, sellingAmount, sellingTime);
    }
    
    // show the current limit orders (first seller then buyer parameters)
    function pendingList() public view returns(string[] memory, int[] memory, int[] memory, string[] memory, int[] memory, int[] memory) {
        uint len1 = sell.length;
        uint len2 = buy.length;
        string[] memory sellerName = new string[](len1);
        int[] memory sellingPrice = new int[](len1);
        int[] memory sellingAmount = new int[](len1);
        string[] memory buyerName = new string[](len2);
        int[] memory buyingPrice = new int[](len2);
        int[] memory buyingAmount = new int[](len2);

        for (uint i = 0; i < len1; ++i) {
            sellerName[i] = name[sell[i].seller];
            sellingPrice[i] = sell[i].price;
            sellingAmount[i] = sell[i].amount;
        }
        for(uint j = 0; j < len2; ++j) {
            buyerName[j] = name[buy[j].buyer];
            buyingPrice[j] = buy[j].price;
            buyingAmount[j] = buy[j].amount;
        }

        return (sellerName, sellingPrice, sellingAmount, buyerName, buyingPrice, buyingAmount);
    }

    //充值
    function deposit() public payable {
        //nothing to do
        balance[msg.sender] =  balance[msg.sender]+msg.value;
    }

    // 获取余额
    function getBalance(address _userAddr) public view returns (string memory, int) {
        for (uint i = 0; i < users.length; ++i) {
            if (users[i].addr == _userAddr)
                return (name[_userAddr], balance[_userAddr]);
        }
        return ("User not registered.", 3);
    }
    
}
