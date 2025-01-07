# Cairo ERC4626 Component [inflation attack free]

An implementation of ERC4626 Component in Cairo. Forked from https://github.com/0xEniotna/ERC4626. Below is the original readme. 
--------

I used the [OZ solidity](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol#L239) implementation. It is itself inspired from YieldBox codebase that has an inflation attack protection. Shares are virtually minted which reduces the issue.

On inflation attack: https://blog.openzeppelin.com/a-novel-defense-against-erc4626-inflation-attacks
https://docs.openzeppelin.com/contracts/4.x/erc4626

I forked this repo https://github.com/0xK3K/starknet-ERC4626 and improved the codebase with the latest cairo version. Thanks @0xK3K !
