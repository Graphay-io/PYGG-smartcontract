import { TradeType, CurrencyAmount, Percent, Token } from '@uniswap/sdk-core';
import {
  AlphaRouter,
  SwapOptionsSwapRouter02,
  SwapRoute,
  SwapType,
} from '@uniswap/smart-order-router';
import { provider, ethers } from 'ethers';
import { BaseProvider } from '@ethersproject/providers';

function countDecimals(x: number): number {
  if (Math.floor(x) === x) {
    return 0;
  }
  return x.toString().split('.')[1].length || 0;
}

export function fromReadableAmount(amount: number, decimals: number): bigint {
  const extraDigits = 10n ** BigInt(countDecimals(amount));
  const adjustedAmount = BigInt(Math.round(amount * Number(extraDigits)));
  return (adjustedAmount * 10n ** BigInt(decimals)) / extraDigits;
}

const mainnetProvider: providers.JsonRpcProvider = new providers.JsonRpcProvider(
  'https://polygon-mainnet.g.alchemy.com/v2/qQEFT94UicGYHQhWXdwVWz1IPEXIYN5K'
);

export function getMainnetProvider(): providers.JsonRpcProvider {
  return mainnetProvider;
}

export async function generateRoute(_sourceToken: string,_destinationToken: string): Promise<SwapRoute | null | any> {
  const router = new AlphaRouter({
    chainId: 137,
    provider: mainnetProvider as unknown as BaseProvider,
  });

  const SMARTCONTRACT = '0x6feeb2f43c99661513f482a4a1dde0e81e8fca1f';

  const options: SwapOptionsSwapRouter02 = {
    recipient: SMARTCONTRACT,
    slippageTolerance: new Percent(5, 10),
    deadline: Math.floor(Date.now() / 1000 + 1800),
    type: SwapType.SWAP_ROUTER_02,
  };

  const route = await router.route(
    CurrencyAmount.fromRawAmount(
      new Token(137, _sourceToken, 18, 'SRC', 'SRC'),
      '100000000000000000'
    ),
    new Token(137, _destinationToken, 18, 'DST', 'DST'),
    TradeType.EXACT_INPUT,
    options
  );
  console.log("route?.trade.routes", route?.trade.routes.map((route:any) => {
    return {
      addresses: route.path.map((token: any) => token.address),
    };
  }));
  return route?.trade.routes.map((route) => {
    return {
      addresses: route.path.map((token: any) => token.address),
      version: route.protocol,
      fees: route.pools.map((pool: any) => pool.fee),
    };
  });
}

function encodePath(path: string[], fees: number[]): string {
  if (path.length !== fees.length + 1) {
    throw new Error('path/fee lengths do not match');
  }

  let encoded = '0x';
  for (let i = 0; i < fees.length; i++) {
    // Encode token address (20 bytes)
    encoded += path[i].slice(2).padStart(40, '0');
    // Encode fee (3 bytes)
    encoded += fees[i].toString(16).padStart(6, '0');
  }
  // Encode the final token address
  encoded += path[path.length - 1].slice(2).padStart(40, '0');

  return encoded.toLowerCase();
}

export async function getEncodedSwapPath(
  sourceToken: string,
  destinationToken: string,
): Promise<string[]> {
  const route = await generateRoute(sourceToken,destinationToken);

  if (!route) {
    throw new Error('Route generation failed');
  }

  const path = route[0].addresses.flat();
  
  const fees = route[0].fees;

  let encodedPath: string;
  if (route[0].version === "V2") {
    // Encode path for Uniswap V2
    encodedPath = ethers.utils.defaultAbiCoder.encode(['address[]'], [path]);
  } else if (route[0].version === "V3") {
    // Encode path for Uniswap V3
    encodedPath = encodePath(path, fees);
  } else {
    throw new Error('Unsupported version');
  }

  return [encodedPath];
}

getEncodedSwapPath("0xA3f751662e282E83EC3cBc387d225Ca56dD63D3A", "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270").then((res) => {
  console.log(res);
});
