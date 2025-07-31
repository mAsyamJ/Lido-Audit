// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IOracleProvider {
    /**
     * @notice Get the price of a asset
     * @param asset The address of the asset
     * @return price The price of the asset
     */
    function getPrice(address asset) external view returns (uint256);
}
