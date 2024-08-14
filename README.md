# Lucidly MasterVault Codebase

This is a weighted stableswap implementation. The arcitecture is forked from the yETH design - https://github.com/yearn/yETH/blob/main/whitepaper/derivation.pdf

The following is deployed on Ethereum Mainnet.
Deployed Addresses for PufMVT -

| Contract    | Address                                    |
| ----------- | ------------------------------------------ |
| Pool        | 0x8dBE744F6558F36d34574a0a6eCA5A8dAa827235 |
| Pool Token  | 0x720e323B5e84945f70A8196BDa3dC1465b457551 |
| MasterVault | 0xfDcDEE4c6fA8b4DBF8e44c30825d2Ab80fd3F0a1 |

The PufEth MasterVault consists of the following tokens -

| Contract                                | Address                                    |
| --------------------------------------- | ------------------------------------------ |
| PufEth                                  | 0x8dBE744F6558F36d34574a0a6eCA5A8dAa827235 |
| Curve.fi pufETH/wstETH (pufETHwstE)     | 0xEEda34A377dD0ca676b9511EE1324974fA8d980D |
| Curve.fi wETH/pufETH (wETHpufETH)       | 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1 |
| yPT-pufETH Yearn Auto-Rolling Pendle PT | 0x66017371c032Cd5a67Fec6913A9e37d5bd1C690c |

Upcoming integrations for liquidity venues are Pendle LPT, Morpho and GammaSwap.
