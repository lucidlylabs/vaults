# Lucidly MasterVault Codebase

This is a weighted stableswap implementation. The arcitecture is forked from the yETH design - https://github.com/yearn/yETH/blob/main/whitepaper/derivation.pdf

Deployed Addresses for PufMVT -

| Contract    | Address                                    |
| ----------- | ------------------------------------------ |
| Pool        | 0x82Fbc848eeCeC6D0a2eBdC8A9420826AE8d2952d |
| Pool Token  | 0x608C9fD78276F8Fae37517129D653803A92ea53A |
| MasterVault | 0xD3Fd1d45499c8500e8009A31c795C7e01CCD7a12 |

The PufEth MasterVault consists of the following tokens -

| Contract                                            | Address                                    | Rate Provider Address                      |
| --------------------------------------------------- | ------------------------------------------ | ------------------------------------------ |
| PufEth                                              | 0xD9A442856C234a39a81a089C06451EBAa4306a72 | 0xC4EF2c4B4eD79CD7639AF070d4a6A82eEF5edd4f |
| Curve.fi pufETH/wstETH (pufETHwstE)                 | 0xEEda34A377dD0ca676b9511EE1324974fA8d980D | 0xC4EF2c4B4eD79CD7639AF070d4a6A82eEF5edd4f |
| Curve.fi wETH/pufETH (wETHpufETH)                   | 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1 | 0x60d4BCab4A8b1849Ca19F6B4a6EaB26A66496267 |
| Morpho PufEthWeth Market 86 lltv (pufethweth86lltv) | 0xeC3B2CC4C6a8fC9a13620A91622483b56E2E6fD9 | 0x3C730BC8Ff9d7D51395c180c409597ae80A63056 |

Upcoming integrations for liquidity venues are Pendle LPT, Pendle PT and GammaSwap.
