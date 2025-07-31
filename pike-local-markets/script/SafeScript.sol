// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console, console2, stdJson, VmSafe} from "forge-std/Script.sol";
import {Surl} from "../lib/surl/src/Surl.sol";

abstract contract SafeScript is Script {
    using stdJson for string;
    using Surl for *;

    string private constant VERSION = "1.3.0";
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;
    bytes32 private constant SAFE_TX_TYPEHASH =
        0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8;

    address private SAFE_MULTISEND_ADDRESS;
    uint256 private chainId;
    string private SAFE_API_BASE_URL;
    string private constant SAFE_API_MULTISIG_SEND = "/multisig-transactions/";
    bytes32 private walletType;
    uint256 private mnemonicIndex;
    bytes32 private privateKey;
    address private safe;

    bytes32 private constant LOCAL = keccak256("local");
    bytes32 private constant LEDGER = keccak256("ledger");

    enum Operation {
        CALL,
        DELEGATECALL
    }

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        Operation operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
        address refundReceiver;
        uint256 nonce;
        bytes32 txHash;
        bytes signature;
    }

    bytes[] public encodedTxns;

    function configureSafe(address safe_, uint256 chainId_) internal {
        safe = safe_;
        chainId = chainId_;

        if (chainId == 1) {
            SAFE_API_BASE_URL =
                "https://safe-transaction-mainnet.safe.global/api/v1/safes/";
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else if (chainId == 11_155_111) {
            SAFE_API_BASE_URL =
                "https://safe-transaction-sepolia.safe.global/api/v1/safes/";
        } else if (chainId == 56) {
            SAFE_API_BASE_URL = "https://safe-transaction-bsc.safe.global/api/v1/safes/";
        } else if (chainId == 10) {
            SAFE_API_BASE_URL =
                "https://safe-transaction-optimism.safe.global/api/v1/safes/";
        } else if (chainId == 8453) {
            SAFE_API_BASE_URL = "https://safe-transaction-base.safe.global/api/v1/safes/";
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else if (chainId == 84_532) {
            SAFE_API_BASE_URL =
                "https://safe-transaction-base-sepolia.safe.global/api/v1/safes/";
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else if (chainId == 42_161) {
            SAFE_API_BASE_URL =
                "https://safe-transaction-arbitrum.safe.global/api/v1/safes/";
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else if (chainId == 43_114) {
            SAFE_API_BASE_URL =
                "https://safe-transaction-avalanche.safe.global/api/v1/safes/";
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else {
            revert("Unsupported chain");
        }

        walletType = keccak256(abi.encodePacked(vm.envString("WALLET_TYPE")));
        if (walletType == LOCAL) {
            privateKey = vm.envBytes32("PRIVATE_KEY");
        } else if (walletType == LEDGER) {
            mnemonicIndex = vm.envUint("MNEMONIC_INDEX");
        } else {
            revert("Unsupported wallet type");
        }
    }

    function addToBatch(address to_, uint256 value_, bytes memory data_) internal {
        encodedTxns.push(
            abi.encodePacked(Operation.CALL, to_, value_, data_.length, data_)
        );
    }

    function executeBatch(bool send_) internal {
        Transaction memory _tx = _createBatch();
        if (send_) {
            _tx = _signTransaction(_tx);
            _sendTransaction(_tx);
        }
    }

    function executeSingle(address to_, uint256 value_, bytes memory data_, bool send_)
        internal
    {
        Transaction memory _tx = _createSingleTx(to_, value_, data_);
        if (send_) {
            _tx = _signTransaction(_tx);
            _sendTransaction(_tx);
        }
    }

    function _createBatch() private returns (Transaction memory _tx) {
        _tx.to = SAFE_MULTISEND_ADDRESS;
        _tx.value = 0;
        _tx.operation = Operation.CALL;
        bytes memory data;
        uint256 len = encodedTxns.length;
        for (uint256 i; i < len; ++i) {
            data = bytes.concat(data, encodedTxns[i]);
        }
        _tx.data = abi.encodeWithSignature("multiSend(bytes)", data);
        _tx.nonce = _getNonce();
        _tx.txHash = _getTransactionHash(_tx);
    }

    function _createSingleTx(address to_, uint256 value_, bytes memory data_)
        private
        returns (Transaction memory _tx)
    {
        _tx.to = to_;
        _tx.value = value_;
        _tx.operation = Operation.CALL;
        _tx.data = data_;
        _tx.nonce = _getNonce();
        _tx.txHash = _getTransactionHash(_tx);
    }

    function _signTransaction(Transaction memory tx_)
        private
        returns (Transaction memory)
    {
        string memory typedData = _getTypedData(tx_);
        console.log("Typed data to sign: %s", typedData);
        string memory commandStart = "cast wallet sign ";
        string memory wallet;
        if (walletType == LOCAL) {
            wallet = string.concat("--private-key ", vm.toString(privateKey), " ");
        } else if (walletType == LEDGER) {
            wallet = string.concat(
                "--ledger --mnemonic-index ", vm.toString(mnemonicIndex), " "
            );
        }
        string memory commandEnd = "--data ";
        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat(commandStart, wallet, commandEnd, "'", typedData, "'");
        console.log("Executing command: %s", inputs[2]);
        bytes memory signature = vm.ffi(inputs);
        console.log("Raw signature: %s", vm.toString(signature));
        console.log("Signature length: %s", signature.length);
        tx_.signature = signature;
        return tx_;
    }

    function _sendTransaction(Transaction memory tx_) private {
        string memory endpoint = _getSafeAPIEndpoint();
        console.log("Sending to endpoint: %s", endpoint);
        console.log("Sender derived from key: %s", vm.addr(uint256(privateKey)));
        console.log("Transaction hash: %s", vm.toString(tx_.txHash));
        console.log("Signature: %s", vm.toString(tx_.signature));
        string memory placeholder = "";
        placeholder.serialize("safe", safe);
        placeholder.serialize("to", tx_.to);
        placeholder.serialize("value", tx_.value);
        placeholder.serialize("data", tx_.data);
        placeholder.serialize("operation", uint256(tx_.operation));
        placeholder.serialize("safeTxGas", tx_.safeTxGas);
        placeholder.serialize("baseGas", tx_.baseGas);
        placeholder.serialize("gasPrice", tx_.gasPrice);
        placeholder.serialize("nonce", tx_.nonce);
        placeholder.serialize("gasToken", address(0));
        placeholder.serialize("refundReceiver", address(0));
        placeholder.serialize("contractTransactionHash", tx_.txHash);
        placeholder.serialize("signature", tx_.signature);
        string memory payload =
            placeholder.serialize("sender", vm.addr(uint256(privateKey))); // Use derived address
        console.log("Payload: %s", payload);
        (uint256 status, bytes memory data) = endpoint.post(_getHeaders(), payload);
        console.log("API response status: %s, data: %s", status, string(data));
        if (status == 201) {
            console2.log("Transaction sent successfully");
        } else {
            revert("Send transaction failed!");
        }
    }

    function _getTransactionHash(Transaction memory tx_) private view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                hex"1901",
                keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, chainId, safe)),
                keccak256(
                    abi.encode(
                        SAFE_TX_TYPEHASH,
                        tx_.to,
                        tx_.value,
                        keccak256(tx_.data),
                        tx_.operation,
                        tx_.safeTxGas,
                        tx_.baseGas,
                        tx_.gasPrice,
                        address(0),
                        address(0),
                        tx_.nonce
                    )
                )
            )
        );
    }

    function _getTypedData(Transaction memory tx_) private returns (string memory) {
        // Define domain and transaction types as string arrays
        string[] memory domainTypes = new string[](2);
        domainTypes[0] = '{"name":"verifyingContract","type":"address"}';
        domainTypes[1] = '{"name":"chainId","type":"uint256"}';
        string[] memory txnTypes = new string[](10);
        txnTypes[0] = '{"name":"to","type":"address"}';
        txnTypes[1] = '{"name":"value","type":"uint256"}';
        txnTypes[2] = '{"name":"data","type":"bytes"}';
        txnTypes[3] = '{"name":"operation","type":"uint8"}';
        txnTypes[4] = '{"name":"safeTxGas","type":"uint256"}';
        txnTypes[5] = '{"name":"baseGas","type":"uint256"}';
        txnTypes[6] = '{"name":"gasPrice","type":"uint256"}';
        txnTypes[7] = '{"name":"gasToken","type":"address"}';
        txnTypes[8] = '{"name":"refundReceiver","type":"address"}';
        txnTypes[9] = '{"name":"nonce","type":"uint256"}';

        // Manually serialize arrays to JSON
        string memory domainTypesJson = "[";
        for (uint256 i = 0; i < domainTypes.length; i++) {
            domainTypesJson = string.concat(domainTypesJson, domainTypes[i]);
            if (i < domainTypes.length - 1) {
                domainTypesJson = string.concat(domainTypesJson, ",");
            }
        }
        domainTypesJson = string.concat(domainTypesJson, "]");

        string memory txnTypesJson = "[";
        for (uint256 i = 0; i < txnTypes.length; i++) {
            txnTypesJson = string.concat(txnTypesJson, txnTypes[i]);
            if (i < txnTypes.length - 1) {
                txnTypesJson = string.concat(txnTypesJson, ",");
            }
        }
        txnTypesJson = string.concat(txnTypesJson, "]");

        string memory types = string(
            abi.encodePacked(
                '{"EIP712Domain":', domainTypesJson, ',"SafeTx":', txnTypesJson, "}"
            )
        );

        // Break message construction into smaller parts
        string memory messagePart1 = string(
            abi.encodePacked(
                '{"to":"',
                vm.toString(tx_.to),
                '","value":',
                vm.toString(tx_.value),
                ',"data":"',
                vm.toString(tx_.data),
                '","operation":',
                vm.toString(uint256(tx_.operation))
            )
        );

        string memory messagePart2 = string(
            abi.encodePacked(
                ',"safeTxGas":',
                vm.toString(tx_.safeTxGas),
                ',"baseGas":',
                vm.toString(tx_.baseGas),
                ',"gasPrice":',
                vm.toString(tx_.gasPrice)
            )
        );

        string memory messagePart3 = string(
            abi.encodePacked(
                ',"gasToken":"0x0000000000000000000000000000000000000000"',
                ',"refundReceiver":"0x0000000000000000000000000000000000000000"',
                ',"nonce":',
                vm.toString(tx_.nonce),
                "}"
            )
        );

        string memory message = string.concat(messagePart1, messagePart2, messagePart3);

        string memory domain = string(
            abi.encodePacked(
                '{"verifyingContract":"',
                vm.toString(safe),
                '","chainId":',
                vm.toString(chainId),
                "}"
            )
        );

        string memory payload = string(
            abi.encodePacked(
                '{"types":',
                types,
                ',"primaryType":"SafeTx"',
                ',"domain":',
                domain,
                ',"message":',
                message,
                "}"
            )
        );

        return _stripSlashQuotes(payload);
    }

    function _stripSlashQuotes(string memory str_) private returns (string memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat("sed 's/\\\\\"/\"/g' <<< '", str_, "'");
        bytes memory res = vm.ffi(inputs);
        return string(res);
    }

    function _getNonce() private returns (uint256) {
        string memory endpoint = string.concat(_getSafeAPIEndpoint(), "?limit=1");
        (uint256 status, bytes memory data) = endpoint.get();
        if (status == 200) {
            string memory resp = string(data);
            uint256 count = resp.readUint(".count");
            if (count == 0) return 0;
            return resp.readUint(".results[0].nonce") + 1;
        } else {
            revert("Get nonce failed!");
        }
    }

    function _getSafeAPIEndpoint() private view returns (string memory) {
        return string.concat(SAFE_API_BASE_URL, vm.toString(safe), SAFE_API_MULTISIG_SEND);
    }

    function _getHeaders() private pure returns (string[] memory) {
        string[] memory headers = new string[](1);
        headers[0] = "Content-Type: application/json";
        return headers;
    }
}
