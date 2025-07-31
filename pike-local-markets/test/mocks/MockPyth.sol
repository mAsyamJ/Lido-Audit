//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPyth, PythStructs} from "@pythnetwork//IPyth.sol";

contract MockPyth is IPyth {
    int64 public price;
    uint64 public conf;
    int32 public expo;

    function setData(int64 _price, uint64 _conf, int32 _expo) external {
        price = _price;
        conf = _conf;
        expo = _expo;
    }

    function getPriceUnsafe(bytes32)
        external
        view
        override
        returns (PythStructs.Price memory)
    {
        return PythStructs.Price(price, conf, expo, 0);
    }

    function getPriceNoOlderThan(bytes32, uint256)
        external
        view
        override
        returns (PythStructs.Price memory)
    {
        if (price == 0) {
            revert();
        }

        return PythStructs.Price(price, conf, expo, 0);
    }

    function getEmaPriceUnsafe(bytes32)
        external
        view
        override
        returns (PythStructs.Price memory)
    {
        return PythStructs.Price(price, conf, expo, 0);
    }

    function getEmaPriceNoOlderThan(bytes32, uint256)
        external
        view
        override
        returns (PythStructs.Price memory)
    {
        return PythStructs.Price(price, conf, expo, 0);
    }

    function updatePriceFeeds(bytes[] calldata updateData) external payable {}

    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata publishTimes
    ) external payable override {}

    function getUpdateFee(bytes[] calldata updateData)
        external
        view
        returns (uint256 feeAmount)
    {}

    function parsePriceFeedUpdates(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    ) external payable returns (PythStructs.PriceFeed[] memory priceFeeds) {}

    function parsePriceFeedUpdatesUnique(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    ) external payable returns (PythStructs.PriceFeed[] memory priceFeeds) {}
}
