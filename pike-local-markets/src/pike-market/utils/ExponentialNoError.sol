// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Exponential module for storing fixed-precision decimals using user-defined value types
 * @author Compound (modified)
 * @notice Uses user-defined value types for better performance
 */
library ExponentialNoError {
    type Exp is uint256;
    type Double is uint256;

    uint256 constant expScale = 1e18;
    uint256 constant doubleScale = 1e36;

    // Conversion functions
    function toExp(uint256 value) internal pure returns (Exp) {
        return Exp.wrap(value);
    }

    function toDouble(uint256 value) internal pure returns (Double) {
        return Double.wrap(value);
    }

    /**
     * @dev Truncates the given exp to a whole number value.
     */
    function truncate(Exp value) internal pure returns (uint256) {
        return Exp.unwrap(value) / expScale;
    }

    /**
     * @dev Multiply an Exp by a scalar, then truncate to return an unsigned integer.
     */
    function mul_ScalarTruncate(Exp value, uint256 scalar)
        internal
        pure
        returns (uint256)
    {
        return truncate(mul_(value, scalar));
    }

    /**
     * @dev Multiply an Exp by a scalar, truncate, then add to an unsigned integer.
     */
    function mul_ScalarTruncateAddUInt(Exp value, uint256 scalar, uint256 addend)
        internal
        pure
        returns (uint256)
    {
        return add_(truncate(mul_(value, scalar)), addend);
    }

    function lessThanExp(Exp left, Exp right) internal pure returns (bool) {
        return Exp.unwrap(left) < Exp.unwrap(right);
    }

    function lessThanOrEqualExp(Exp left, Exp right) internal pure returns (bool) {
        return Exp.unwrap(left) <= Exp.unwrap(right);
    }

    function add_(Exp a, Exp b) internal pure returns (Exp) {
        return toExp(add_(Exp.unwrap(a), Exp.unwrap(b)));
    }

    function add_(Double a, Double b) internal pure returns (Double) {
        return toDouble(add_(Double.unwrap(a), Double.unwrap(b)));
    }

    function add_(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function sub_(Exp a, Exp b) internal pure returns (Exp) {
        return toExp(sub_(Exp.unwrap(a), Exp.unwrap(b)));
    }

    function sub_(Double a, Double b) internal pure returns (Double) {
        return toDouble(sub_(Double.unwrap(a), Double.unwrap(b)));
    }

    function sub_(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    function mul_(Exp a, Exp b) internal pure returns (Exp) {
        return toExp(mul_(Exp.unwrap(a), Exp.unwrap(b)) / expScale);
    }

    function mul_(Exp a, uint256 b) internal pure returns (Exp) {
        return toExp(mul_(Exp.unwrap(a), b));
    }

    function mul_(uint256 a, Exp b) internal pure returns (uint256) {
        return mul_(a, Exp.unwrap(b)) / expScale;
    }

    function mul_(Double a, Double b) internal pure returns (Double) {
        return toDouble(mul_(Double.unwrap(a), Double.unwrap(b)) / doubleScale);
    }

    function mul_(Double a, uint256 b) internal pure returns (Double) {
        return toDouble(mul_(Double.unwrap(a), b));
    }

    function mul_(uint256 a, Double b) internal pure returns (uint256) {
        return mul_(a, Double.unwrap(b)) / doubleScale;
    }

    function mul_(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    function div_(Exp a, Exp b) internal pure returns (Exp) {
        return toExp(div_(mul_(Exp.unwrap(a), expScale), Exp.unwrap(b)));
    }

    function div_(Exp a, uint256 b) internal pure returns (Exp) {
        return toExp(div_(Exp.unwrap(a), b));
    }

    function div_(uint256 a, Exp b) internal pure returns (uint256) {
        return div_(mul_(a, expScale), Exp.unwrap(b));
    }

    function div_(Double a, Double b) internal pure returns (Double) {
        return toDouble(div_(mul_(Double.unwrap(a), doubleScale), Double.unwrap(b)));
    }

    function div_(Double a, uint256 b) internal pure returns (Double) {
        return toDouble(div_(Double.unwrap(a), b));
    }

    function div_(uint256 a, Double b) internal pure returns (uint256) {
        return div_(mul_(a, doubleScale), Double.unwrap(b));
    }

    function div_(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }
}
