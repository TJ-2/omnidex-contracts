// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IOmniDexInterfaces.sol";
import "./interfaces/IDepositTelos.sol";
import "./ImmutableOwnable.sol";

/**
 * Single asset leveraged reborrowing strategy on OMNIDEX, chain agnostic.
 * Position managed by this contract, with full ownership and control by Owner.
 * Monitor position health to avoid liquidation.
 */
contract OmniDexLoop is ImmutableOwnable {
    using SafeERC20 for ERC20;

    uint256 public constant USE_VARIABLE_DEBT = 2;
    uint256 public constant SAFE_BUFFER = 10; // wei

    ERC20 public immutable SUPPLY_ASSET; // solhint-disable-line
    ERC20 public immutable BORROW_ASSET; // solhint-disable-line
    IDepositTelos public immutable DEPOSIT_TELOS; // solhint-disable-line
    ILendingPool public immutable LENDING_POOL; // solhint-disable-line
    IOmniDexIncentivesController public immutable INCENTIVES; // solhint-disable-line

    /**
     * @param owner The contract owner, has complete ownership, immutable
     * @param supply_asset The target underlying supply_asset ex. USDC
     * @param lendingPool The deployed OMNIDEX ILendingPool
     * @param incentives The deployed OMNIDEX IOmniDexIncentivesController
     */
    constructor(
        address owner,
        address supply_asset,
        address borrow_asset,
        address depositTelos,
        address lendingPool,
        address incentives
    ) ImmutableOwnable(owner) {
        require(supply_asset != address(0) && lendingPool != address(0) && incentives != address(0), "address 0");

        SUPPLY_ASSET = ERC20(supply_asset);
        BORROW_ASSET = ERC20(borrow_asset);
        DEPOSIT_TELOS = IDepositTelos(depositTelos);
        LENDING_POOL = ILendingPool(lendingPool);
        INCENTIVES = IOmniDexIncentivesController(incentives);
    }

    // ---- views ----

    function getSupplyAndBorrowAssets() public view returns (address[] memory assets) {
        DataTypes.ReserveData memory supply_data = LENDING_POOL.getReserveData(address(SUPPLY_ASSET));
        DataTypes.ReserveData memory borrow_data = LENDING_POOL.getReserveData(address(BORROW_ASSET));

        assets = new address[](2);
        assets[0] = supply_data.aTokenAddress;
        assets[1] = borrow_data.variableDebtTokenAddress;
    }

    /**
     * @return The SUPPLY_ASSET price in ETH according to OmniDex PriceOracle, used internally for all SUPPLY_ASSET amounts calculations
     */
    function getSupplyAssetPrice() public view returns (uint256) {
        return IOmniDexPriceOracle(LENDING_POOL.getAddressesProvider().getPriceOracle()).getAssetPrice(address(SUPPLY_ASSET));
    }

    /**
     * @return The BORROW_ASSET price in ETH according to OmniDex PriceOracle, used internally for all BORROW_ASSET amounts calculations
     */
    function getBorrowAssetPrice() public view returns (uint256) {
        return IOmniDexPriceOracle(LENDING_POOL.getAddressesProvider().getPriceOracle()).getAssetPrice(address(BORROW_ASSET));
    }

    /**
     * @return total supply balance in SUPPLY_ASSET
     */
    function getSupplyBalance() public view returns (uint256) {
        (uint256 totalCollateralETH, , , , , ) = getPositionData();
        return (totalCollateralETH * (10**SUPPLY_ASSET.decimals())) / getSupplyAssetPrice();
    }

    /**
     * @return total borrow balance in BORROW_ASSET
     */
    function getBorrowBalance() public view returns (uint256) {
        (, uint256 totalDebtETH, , , , ) = getPositionData();
        return (totalDebtETH * (10**BORROW_ASSET.decimals())) / getBorrowAssetPrice();
    }

    /**
     * @return available liquidity in BORROW_ASSET
     */
    function getLiquidity() public view returns (uint256) {
        (, , uint256 availableBorrowsETH, , , ) = getPositionData();
        return (availableBorrowsETH * (10**BORROW_ASSET.decimals())) / getSupplyAssetPrice();  // !? Changed from Supply asset to Borrow asset.
    }

    /**
     * @return SUPPLY_ASSET balanceOf(this)
     */
    function getSupplyAssetBalance() public view returns (uint256) {
        return SUPPLY_ASSET.balanceOf(address(this));
    }

    /**
     * @return BORROW_ASSET balanceOf(this)
     */
    function getBorrowAssetBalance() public view returns (uint256) {
        return BORROW_ASSET.balanceOf(address(this));
    }

    /**
     * @return Pending rewards
     */
    function getPendingRewards() public view returns (uint256) {
        return INCENTIVES.getRewardsBalance(getSupplyAndBorrowAssets(), address(this));
    }

    /**
     * Position data from OmniLend
     */
    function getPositionData()
        public
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return LENDING_POOL.getUserAccountData(address(this));
    }

    /**
     * @return LTV of SUPPLY_ASSET in 4 decimals ex. 82.5% == 8250
     */
    function getLTV() public view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory config = LENDING_POOL.getConfiguration(address(SUPPLY_ASSET));
        return config.data & 0xffff; // bits 0-15 in BE
    }

    // ---- unrestricted ----

    /**
     * Claims and transfers all pending rewards to OWNER
     */
    function claimRewardsToOwner() external {
        INCENTIVES.claimRewards(getSupplyAndBorrowAssets(), type(uint256).max, OWNER);
    }

    // ---- main ----

    /**
     * @param iterations - Loop count
     * @return Liquidity at end of the loop
     */
    function enterPositionFully(uint256 iterations, address _address) external onlyOwner returns (uint256) {
        return enterPosition(SUPPLY_ASSET.balanceOf(msg.sender), iterations, _address);
    }

    /**
     * @param principal - SUPPLY_ASSET transferFrom sender amount, can be 0
     * @param iterations - Loop count
     * @return Liquidity at end of the loop
     */
    function enterPosition(uint256 principal, uint256 iterations, address _address) public onlyOwner returns (uint256) {
        if (principal > 0) {
            SUPPLY_ASSET.safeTransferFrom(msg.sender, address(this), principal);
        }

        if (getSupplyAssetBalance() > 0) {
            _supply(getSupplyAssetBalance());
        }

        for (uint256 i = 0; i < iterations; i++) {
            
            _borrow(getLiquidity() - SAFE_BUFFER);
            // Swap wTLOS back to xTLOS to reloop strategy
            DEPOSIT_TELOS.wTLOStoXTLOSConversion(getBorrowAssetBalance(), _address);
            _supply(getSupplyAssetBalance());
        }

        return getLiquidity();
    }

    /**
     * @param iterations - MAX loop count
     * @return Withdrawn amount of SUPPLY_ASSET to OWNER
     */
    function exitPosition(uint256 iterations) external onlyOwner returns (uint256) {
        (, , , , uint256 ltv, ) = getPositionData(); // 4 decimals

        for (uint256 i = 0; i < iterations && getBorrowBalance() > 0; i++) {
            _redeemSupply(((getLiquidity() * 1e4) / ltv) - SAFE_BUFFER);
            _repayBorrow(getSupplyAssetBalance());
        }

        if (getBorrowBalance() == 0) {
            _redeemSupply(type(uint256).max);
        }

        return _withdrawToOwner(address(SUPPLY_ASSET));
    }

    // ---- internals, public onlyOwner in case of emergency ----

    /**
     * amount in SUPPLY_ASSET
     */
    function _supply(uint256 amount) public onlyOwner {
        SUPPLY_ASSET.safeIncreaseAllowance(address(LENDING_POOL), amount);
        LENDING_POOL.deposit(address(SUPPLY_ASSET), amount, address(this), 0);
    }

    /**
     * amount in SUPPLY_ASSET
     */
    function _borrow(uint256 amount) public onlyOwner {
        LENDING_POOL.borrow(address(BORROW_ASSET), amount, USE_VARIABLE_DEBT, 0, address(this));
    }

    /**
     * amount in SUPPLY_ASSET
     */
    function _redeemSupply(uint256 amount) public onlyOwner {
        LENDING_POOL.withdraw(address(SUPPLY_ASSET), amount, address(this));
    }

    /**
     * amount in SUPPLY_ASSET
     */
    function _repayBorrow(uint256 amount) public onlyOwner {
        SUPPLY_ASSET.safeIncreaseAllowance(address(LENDING_POOL), amount);
        LENDING_POOL.repay(address(BORROW_ASSET), amount, USE_VARIABLE_DEBT, address(this));
    }

    function _withdrawToOwner(address asset) public onlyOwner returns (uint256) {
        uint256 balance = ERC20(asset).balanceOf(address(this));
        ERC20(asset).safeTransfer(OWNER, balance);
        return balance;
    }

    // ---- emergency ----

    function emergencyFunctionCall(address target, bytes memory data) external onlyOwner {
        Address.functionCall(target, data);
    }

    function emergencyFunctionDelegateCall(address target, bytes memory data) external onlyOwner {
        Address.functionDelegateCall(target, data);
    }
}