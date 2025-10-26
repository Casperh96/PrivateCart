// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, ebool, euint16, euint64, externalEuint16, externalEuint64 } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

/**
 * PrivateCart (FHE)
 * - Пользователь добавляет позиции в корзину шифрованно.
 * - В ончейн-хранилище остаются только агрегаты:
 *      total (сумма по всем товарам) и catSum[c] (сумма по категориям)
 * - Индекс категории передаётся шифрованно и маршрутизируется через
 *   ebool + select без раскрытия (one-hot по <= MAX_CATS).
 *
 * Категории индексируются 0..MAX_CATS-1 (0:Food,1:Electronics,2:Books,3:Fashion,4:Home,5:Beauty,6:Sports,7:Other).
 * Диапазон цены: uint64 (например, центы).
 */
contract PrivateCart is SepoliaConfig {
    using FHE for *;

    uint16 public constant MAX_CATS = 8;

    struct Cart {
        bool exists;
        address owner;
        euint64 total;
        mapping(uint16 => euint64) catSum; // сумма по каждой категории
    }

    mapping(bytes32 => Cart) private _carts;

    event CartInitialized(bytes32 indexed cartId, address indexed owner);
    event ItemAdded(bytes32 indexed cartId, bytes32 totalHandle);
    event CartMadePublic(bytes32 indexed cartId);

    modifier onlyOwner(bytes32 cartId) {
        require(_carts[cartId].exists, "Cart not found");
        require(_carts[cartId].owner == msg.sender, "Not cart owner");
        _;
    }

    /// @notice Инициализация/сброс корзины для заданного cartId (например keccak256(key)).
    function initCart(bytes32 cartId, address owner) external {
        require(owner != address(0), "Zero owner");

        Cart storage C = _carts[cartId];
        C.exists = true;
        C.owner = owner;
        C.total = FHE.asEuint64(0);
        FHE.allowThis(C.total);

        // обнуляем суммы категорий и разрешаем контракту доступ
        for (uint16 i = 0; i < MAX_CATS; i++) {
            C.catSum[i] = FHE.asEuint64(0);
            FHE.allowThis(C.catSum[i]);
        }

        emit CartInitialized(cartId, owner);
    }

    /**
     * @notice Добавить позицию в корзину (цена и категория шифрованы, один общий proof).
     * @param cartId    Идентификатор корзины (keccak256 от любого ключа).
     * @param priceExt  externalEuint64 (цена в минимальных единицах, например, центы).
     * @param catExt    externalEuint16 (индекс категории 0..MAX_CATS-1).
     * @param proof     Аттестация из Relayer SDK для priceExt и catExt (оба из одного encrypt()).
     */
    function addItem(
        bytes32 cartId,
        externalEuint64 priceExt,
        externalEuint16 catExt,
        bytes calldata proof
    ) external onlyOwner(cartId) {
        Cart storage C = _carts[cartId];

        // Расшифровываем ciphertext-handles (валидация proof)
        euint64 price = FHE.fromExternal(priceExt, proof);
        euint16 cat   = FHE.fromExternal(catExt, proof);

        // Ограничим индекс категории [0..MAX_CATS-1] (иначе инкремент ноль)
        ebool isInRange = FHE.le(cat, FHE.asEuint16(MAX_CATS - 1));
        euint64 effPrice = FHE.select(isInRange, price, FHE.asEuint64(0));

        // total += effPrice
        C.total = FHE.add(C.total, effPrice);
        FHE.allowThis(C.total);            // повторное использование
        FHE.allow(C.total, C.owner);       // приватное чтение владельцем

        // one-hot маршрутизация по категориям без раскрытия индекса
        for (uint16 i = 0; i < MAX_CATS; i++) {
            ebool isCat = FHE.eq(cat, FHE.asEuint16(i));
            euint64 inc = FHE.select(isCat, effPrice, FHE.asEuint64(0));
            C.catSum[i] = FHE.add(C.catSum[i], inc);
            FHE.allowThis(C.catSum[i]);
            FHE.allow(C.catSum[i], C.owner);
        }

        emit ItemAdded(cartId, FHE.toBytes32(C.total));
    }

    /// @notice Сделать агрегаты корзины публично расшифровываемыми (для дашбордов и т.п.).
    function makeCartPublic(bytes32 cartId) external onlyOwner(cartId) {
        Cart storage C = _carts[cartId];
        FHE.makePubliclyDecryptable(C.total);
        for (uint16 i = 0; i < MAX_CATS; i++) {
            FHE.makePubliclyDecryptable(C.catSum[i]);
        }
        emit CartMadePublic(cartId);
    }

    /// -------- Getters (возвращают только handles) --------

    function getTotalHandle(bytes32 cartId) external view returns (bytes32) {
        require(_carts[cartId].exists, "Cart not found");
        return FHE.toBytes32(_carts[cartId].total);
    }

    /// @notice Возвратить массив из MAX_CATS handles для категорий.
    function getCategoryHandles(bytes32 cartId) external view returns (bytes32[MAX_CATS] memory out) {
        require(_carts[cartId].exists, "Cart not found");
        for (uint16 i = 0; i < MAX_CATS; i++) {
            out[i] = FHE.toBytes32(_carts[cartId].catSum[i]);
        }
    }

    function ownerOf(bytes32 cartId) external view returns (address) {
        return _carts[cartId].owner;
    }
}
