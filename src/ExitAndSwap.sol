// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice Мини-интерфейс Uniswap V3 PositionManager
interface INonfungiblePositionManager {
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
    }
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max; 
    }

    /// ↓ заменяем burn() на decreaseLiquidity()
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);
}

/// @notice Мини-интерфейс SwapRouter02 на Base
interface ISwapRouterMinimal {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

/// @notice ERC20-интерфейс
interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

contract ExitAndSwap {
    INonfungiblePositionManager public immutable NPM;
    ISwapRouterMinimal          public immutable SWAP;
    uint24                      public immutable FEE;

    constructor(
        address positionManager, // 0x03a520b32C04BF3bEEf7BEb72e919cf822Ed34F1
        address swapRouter,      // 0x2626664c2603336E57B271c5C0b26F421741e481
        uint24  feeTier          // 500 (0.05%) или 3000 (0.3%)
    ) {
        NPM  = INonfungiblePositionManager(positionManager);
        SWAP = ISwapRouterMinimal(swapRouter);
        FEE  = feeTier;
    }

    /// @notice Decrease liquidity → collect → swap everything → msg.sender
    function exitAndSwap(
        uint256 positionId,
        uint128 liquidity,
        address token0,
        address token1,
        uint256 amountOutMin
    ) external {
        // 1) уменьшаем ликвидность
        NPM.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId:    positionId,
                liquidity:  liquidity,
                amount0Min: 0,
                amount1Min: 0
            })
        );

        // 2) забираем все токены + комиссии
        NPM.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId:    positionId,
                recipient:  address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // 3) определяем, что у нас на балансе
        uint256 bal0 = IERC20(token0).balanceOf(address(this));
        address tokenIn  = bal0 > 0 ? token0 : token1;
        address tokenOut = bal0 > 0 ? token1 : token0;
        uint256 amountIn = bal0 > 0
            ? bal0
            : IERC20(token1).balanceOf(address(this));

        // 4) даём право свапа
        IERC20(tokenIn).approve(address(SWAP), amountIn);

        // 5) свапаем всё tokenIn → tokenOut
        ISwapRouterMinimal.ExactInputSingleParams memory params = ISwapRouterMinimal
            .ExactInputSingleParams({
                tokenIn:           tokenIn,
                tokenOut:          tokenOut,
                fee:               FEE,
                recipient:         msg.sender,
                deadline:          block.timestamp + 300,
                amountIn:          amountIn,
                amountOutMinimum:  amountOutMin,
                sqrtPriceLimitX96: 0
            });
        SWAP.exactInputSingle(params);
    }
}
