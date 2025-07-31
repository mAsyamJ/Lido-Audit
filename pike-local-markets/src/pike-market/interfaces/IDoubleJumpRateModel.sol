// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";

interface IDoubleJumpRateModel is IInterestRateModel {
    event NewInterestParams(
        uint256 baseRatePerSecond,
        uint256 multiplierPerSecond,
        uint256 firstJumpMultiplierPerSecond,
        uint256 secondJumpMultiplierPerSecond,
        uint256 firstKink,
        uint256 secondKink
    );

    /**
     * @notice Configures the parameters for the interest rate model of the protocol.
     * @dev This function sets the base rate, multipliers, and kink points for the interest rate model.
     * All annualized rates are converted to per-second rates for internal calculations.
     * Only callable by the configurator.
     * @param baseRate The base interest rate per year (scaled by 1e18) before utilization hits the first kink.
     * @param initialMultiplier The multiplier per year (scaled by 1e18)
     * that increases the interest rate as utilization increases before the first kink.
     * @param firstKinkMultiplier The additional multiplier per year applied after the first kink point (scaled by 1e18).
     * @param secondKinkMultiplier The additional multiplier per year applied after second kink point (scaled by 1e18).
     * @param firstKink The utilization rate (scaled by 1e18) at which the interest rate "jumps"
     *  according to the first jump multiplier.
     * @param secondKink The utilization rate (scaled by 1e18) at which the interest rate "jumps"
     * according to the second jump multiplier.
     */
    function configureInterestRateModel(
        uint256 baseRate,
        uint256 initialMultiplier,
        uint256 firstKinkMultiplier,
        uint256 secondKinkMultiplier,
        uint256 firstKink,
        uint256 secondKink
    ) external;

    /**
     * @return first and second kinks
     */
    function kinks() external view returns (uint256, uint256);

    /**
     * @return base rate per second
     */
    function baseRatePerSecond() external view returns (uint256);

    /**
     * @return base multiplier, and double jump multipliers
     */
    function multipliers() external pure returns (uint256, uint256, uint256);
}
