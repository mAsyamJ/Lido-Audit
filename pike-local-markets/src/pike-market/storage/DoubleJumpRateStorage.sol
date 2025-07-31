//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract DoubleJumpRateStorage {
    /// @custom:storage-location erc7201:pike.LM.DJR
    struct InterestRateData {
        /**
         * @notice The multiplier of utilization rate that gives the slope of the interest rate
         */
        uint256 multiplierPerSecond;
        /**
         * @notice The base interest rate which is the y-intercept when utilization rate is 0
         */
        uint256 baseRatePerSecond;
        /**
         * @notice The multiplierPerSecond after hitting first specified utilization point
         */
        uint256 firstJumpMultiplierPerSecond;
        /**
         * @notice The multiplierPerSecond after hitting second specified utilization point
         */
        uint256 secondJumpMultiplierPerSecond;
        /**
         * @notice The first utilization point at which the first jump multiplier is applied
         */
        uint256 firstKink;
        /**
         * @notice The second utilization point at which the second jump multiplier is applied
         */
        uint256 secondKink;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.DJR")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_IRM_STORAGE =
        0xed48eb0ad35ca178ca1b2fcca15fd54561240eeda787bde1429143f97eac7300;

    uint256 internal constant BASE = 1e18;

    /**
     * @notice The approximate number of seconds per year that is assumed by the interest rate model
     */
    uint256 internal constant SECONDS_PER_YEAR = 31_536_000;

    function _getIRMStorage() internal pure returns (InterestRateData storage data) {
        bytes32 s = _SLOT_IRM_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
