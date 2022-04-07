// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./crowdsale/Crowdsale.sol";
import "./crowdsale/emission/AllowanceCrowdsale.sol";
import "./crowdsale/validation/CappedCrowdsale.sol";
import "./crowdsale/validation/PausableCrowdsale.sol";
import "./crowdsale/validation/TimedCrowdsale.sol";

contract ContestCrowdsale is Crowdsale, AllowanceCrowdsale, CappedCrowdsale, PausableCrowdsale, TimedCrowdsale {
    constructor(uint256 rate_, address payable wallet_, IERC20 token_, 
                address tokenWallet_,
                uint256 cap_,
                uint256 openingTime_, uint256 closingTime_)
        Crowdsale(rate_, wallet_, token_)
        AllowanceCrowdsale(tokenWallet_)
        CappedCrowdsale(cap_)
        TimedCrowdsale(openingTime_, closingTime_)
    {}

    // The following functions are overrides required by Solidity.

    function _deliverTokens(address beneficiary, uint256 tokenAmount)
        internal
        override(Crowdsale, AllowanceCrowdsale)
    {
        return super._deliverTokens(beneficiary, tokenAmount);
    }

    function _preValidatePurchase(address beneficiary, uint256 weiAmount)
        internal
        view
        override(Crowdsale, CappedCrowdsale, PausableCrowdsale, TimedCrowdsale)
    {
        return super._preValidatePurchase(beneficiary, weiAmount);
    }

}
