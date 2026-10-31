// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts@5.6.1/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts@5.6.1/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts@5.6.1/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@5.6.1/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts@5.6.1/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts@5.6.1/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.6.1/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts@5.6.1/utils/math/Math.sol";

/// @title ArcFxDesk
/// @notice Quote-first, owner-funded USDC-to-EURC desk with 60-second locked quotes.
/// @dev Both tokens must be standard, six-decimal ERC-20s without transfer fees or rebasing.
/// Quotes do not reserve inventory; sufficient EURC must still be available at execution.
/// Fees remain in EURC inventory. There is no oracle, upgrade mechanism, or native-token entry point.
contract ArcFxDesk is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice EURC-per-USDC rate precision; both token amounts use six decimals.
    uint256 public constant RATE_SCALE = 1e18;
    /// @notice Basis-point denominator.
    uint256 public constant BPS = 10_000;
    /// @notice Maximum fee, equivalent to 10% of gross EURC output.
    uint16 public constant MAX_FEE_BPS = 1000;
    /// @notice Quotes may be executed through their expiry timestamp, inclusively.
    uint256 public constant QUOTE_TTL = 60 seconds;

    /// @notice Input token, configured for the deployment network.
    IERC20 public immutable usdc;
    /// @notice Output token, configured for the deployment network.
    IERC20 public immutable eurc;
    /// @notice Current EURC-per-USDC rate scaled by RATE_SCALE.
    uint256 public rate;
    /// @notice Current fee in basis points of gross EURC output.
    uint16 public feeBps;
    /// @notice Maximum input amount for newly requested quotes, in USDC base units.
    uint256 public maxAmountPerSwap;
    /// @notice Identifier assigned to the next quote.
    uint256 public nextQuoteId = 1;

    /// @notice Lifecycle of a quote; expired quotes remain Open but cannot execute.
    enum Status { None, Open, Executed }

    /// @notice Immutable quote terms, except for execution status.
    /// @param user Account authorized to execute this quote.
    /// @param amountIn USDC input in base units.
    /// @param rate Snapshotted rate scaled by RATE_SCALE.
    /// @param estimatedOut Gross EURC output, rounded down.
    /// @param fee EURC fee, rounded down.
    /// @param minReceived Locked net EURC payout.
    /// @param expiry Last timestamp at which execution is allowed.
    /// @param status Quote lifecycle status.
    struct Quote {
        address user;
        uint256 amountIn;
        uint256 rate;
        uint256 estimatedOut;
        uint256 fee;
        uint256 minReceived;
        uint256 expiry;
        Status status;
    }

    /// @notice Quote records indexed by identifier; missing identifiers have status None.
    mapping(uint256 => Quote) public quotes;
    mapping(address => uint256[]) private _quoteIds;

    /// @notice Ownership cannot be renounced.
    error RenounceDisabled();
    /// @notice A token or withdrawal recipient was the zero address.
    error ZeroAddress();
    /// @notice Input and output tokens must differ.
    error IdenticalTokens();
    /// @notice A configured token does not use six decimals.
    error InvalidTokenDecimals(address token, uint8 decimals);
    /// @notice Rates must be nonzero.
    error InvalidRate();
    /// @notice The fee exceeds MAX_FEE_BPS.
    error InvalidFeeBps(uint16 feeBps);
    /// @notice The swap limit must be nonzero.
    error InvalidMaxAmount();
    /// @notice The input amount must be nonzero.
    error InvalidAmount();
    /// @notice The quote input exceeds the current swap limit.
    error AmountExceedsMaximum(uint256 amount, uint256 maximum);
    /// @notice Inventory operations support only the configured USDC and EURC.
    error UnsupportedToken(address token);
    /// @notice The calculated net EURC output is zero.
    error ZeroOutput();
    /// @notice Available EURC is less than the locked payout.
    error InsufficientInventory();
    /// @notice No quote exists with this identifier.
    error QuoteNotFound();
    /// @notice Only an Open quote may execute.
    error QuoteNotOpen();
    /// @notice Only the account that requested a quote may execute it.
    error NotQuoteOwner();
    /// @notice The quote's inclusive expiry has passed.
    error QuoteExpired();
    /// @notice The locked payout is below the caller's requested minimum.
    error SlippageExceeded(uint256 payout, uint256 minReceived);

    /// @notice Emitted when the rate for future quotes changes.
    event RateUpdated(uint256 oldRate, uint256 newRate);
    /// @notice Emitted when the fee for future quotes changes.
    event FeeUpdated(uint16 oldBps, uint16 newBps);
    /// @notice Emitted when the input limit for future quotes changes.
    event MaxAmountUpdated(uint256 oldAmount, uint256 newAmount);
    /// @notice Emitted when inventory is pulled from the owner.
    event InventoryDeposited(address indexed token, address indexed from, uint256 amount);
    /// @notice Emitted when the owner withdraws inventory.
    event InventoryWithdrawn(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted with all locked terms of a newly created quote.
    event QuoteCreated(
        uint256 indexed quoteId,
        address indexed user,
        uint256 amountIn,
        uint256 rate,
        uint256 estimatedOut,
        uint256 fee,
        uint256 minReceived,
        uint256 expiry
    );
    /// @notice Emitted after successful USDC collection and net EURC payment.
    event SettlementRecorded(
        uint256 indexed quoteId,
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee,
        uint256 rate,
        uint256 timestamp
    );

    /// @notice Initializes the owner, network-specific token pair, rate, fee, and 5-USDC limit.
    /// @param initialOwner Initial administrator; ownership transfers require acceptance.
    /// @param usdc_ Six-decimal USDC token address.
    /// @param eurc_ Six-decimal EURC token address.
    /// @param initialRate Initial EURC-per-USDC rate scaled by RATE_SCALE.
    /// @param initialFeeBps Initial EURC fee in basis points.
    constructor(address initialOwner, address usdc_, address eurc_, uint256 initialRate, uint16 initialFeeBps)
        Ownable(initialOwner)
    {
        if (usdc_ == address(0) || eurc_ == address(0)) revert ZeroAddress();
        if (usdc_ == eurc_) revert IdenticalTokens();
        uint8 usdcDecimals = IERC20Metadata(usdc_).decimals();
        if (usdcDecimals != 6) revert InvalidTokenDecimals(usdc_, usdcDecimals);
        uint8 eurcDecimals = IERC20Metadata(eurc_).decimals();
        if (eurcDecimals != 6) revert InvalidTokenDecimals(eurc_, eurcDecimals);
        if (initialRate == 0) revert InvalidRate();
        if (initialFeeBps > MAX_FEE_BPS) revert InvalidFeeBps(initialFeeBps);

        usdc = IERC20(usdc_);
        eurc = IERC20(eurc_);
        rate = initialRate;
        feeBps = initialFeeBps;
        maxAmountPerSwap = 5e6;
        emit RateUpdated(0, initialRate);
        emit FeeUpdated(0, initialFeeBps);
        emit MaxAmountUpdated(0, 5e6);
    }

    /// @notice Updates the rate for new quotes without changing existing quotes.
    function setRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) revert InvalidRate();
        uint256 oldRate = rate;
        rate = newRate;
        emit RateUpdated(oldRate, newRate);
    }

    /// @notice Updates the fee for new quotes without changing existing quotes.
    function setFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert InvalidFeeBps(newFeeBps);
        uint16 oldBps = feeBps;
        feeBps = newFeeBps;
        emit FeeUpdated(oldBps, newFeeBps);
    }

    /// @notice Updates the positive input limit for new quotes only.
    function setMaxAmountPerSwap(uint256 newMaximum) external onlyOwner {
        if (newMaximum == 0) revert InvalidMaxAmount();
        uint256 oldMaximum = maxAmountPerSwap;
        maxAmountPerSwap = newMaximum;
        emit MaxAmountUpdated(oldMaximum, newMaximum);
    }

    /// @notice Renouncing ownership is disabled so the desk can always be unpaused and its inventory recovered.
    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    /// @notice Stops quote creation and settlement; emits OpenZeppelin's Paused event.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes quote creation and settlement; emits OpenZeppelin's Unpaused event.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Pulls supported-token inventory from the owner, including while paused.
    /// @dev The owner must approve this contract before depositing.
    function depositInventory(address token, uint256 amount) external onlyOwner nonReentrant {
        _supportedToken(token).safeTransferFrom(msg.sender, address(this), amount);
        emit InventoryDeposited(token, msg.sender, amount);
    }

    /// @notice Withdraws supported-token inventory to a nonzero recipient, including while paused.
    function withdrawInventory(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        IERC20 asset = _supportedToken(token);
        if (to == address(0)) revert ZeroAddress();
        asset.safeTransfer(to, amount);
        emit InventoryWithdrawn(token, to, amount);
    }

    /// @notice Creates an inventory-checked quote with locked pricing, but does not reserve EURC.
    /// @param amountIn USDC input in six-decimal base units.
    /// @return quoteId The newly assigned quote identifier.
    function requestQuote(uint256 amountIn) external whenNotPaused returns (uint256 quoteId) {
        if (amountIn == 0) revert InvalidAmount();
        if (amountIn > maxAmountPerSwap) revert AmountExceedsMaximum(amountIn, maxAmountPerSwap);
        uint256 quotedRate = rate;
        uint256 estimatedOut = Math.mulDiv(amountIn, quotedRate, RATE_SCALE);
        uint256 fee = Math.mulDiv(estimatedOut, feeBps, BPS);
        uint256 payout = estimatedOut - fee;
        if (payout == 0) revert ZeroOutput();
        if (eurc.balanceOf(address(this)) < payout) revert InsufficientInventory();
        uint256 expiry = block.timestamp + QUOTE_TTL;

        quoteId = nextQuoteId++;
        quotes[quoteId] = Quote({
            user: msg.sender,
            amountIn: amountIn,
            rate: quotedRate,
            estimatedOut: estimatedOut,
            fee: fee,
            minReceived: payout,
            expiry: expiry,
            status: Status.Open
        });
        _quoteIds[msg.sender].push(quoteId);
        emit QuoteCreated(quoteId, msg.sender, amountIn, quotedRate, estimatedOut, fee, payout, expiry);
    }

    /// @notice Settles the caller's unexpired quote exactly once at its locked net payout.
    /// @param quoteId Identifier of the quote to execute.
    /// @param minReceived Caller-supplied minimum EURC output in base units.
    /// @dev USDC allowance is required. Any failed transfer rolls back status and token movement.
    function executeQuote(uint256 quoteId, uint256 minReceived) external nonReentrant whenNotPaused {
        Quote storage quote = quotes[quoteId];
        if (quote.status == Status.None) revert QuoteNotFound();
        if (quote.status != Status.Open) revert QuoteNotOpen();
        if (quote.user != msg.sender) revert NotQuoteOwner();
        if (block.timestamp > quote.expiry) revert QuoteExpired();
        uint256 payout = quote.minReceived;
        if (payout < minReceived) revert SlippageExceeded(payout, minReceived);
        if (eurc.balanceOf(address(this)) < payout) revert InsufficientInventory();

        quote.status = Status.Executed;
        usdc.safeTransferFrom(quote.user, address(this), quote.amountIn);
        eurc.safeTransfer(quote.user, payout);
        emit SettlementRecorded(
            quoteId, quote.user, quote.amountIn, payout, quote.fee, quote.rate, block.timestamp
        );
    }

    /// @notice Returns a complete quote, reverting if its identifier does not exist.
    function getQuote(uint256 quoteId) external view returns (Quote memory) {
        if (quotes[quoteId].status == Status.None) revert QuoteNotFound();
        return quotes[quoteId];
    }

    /// @notice Returns all quote identifiers requested by an account, in creation order.
    function quoteIdsOf(address user) external view returns (uint256[] memory) {
        return _quoteIds[user];
    }

    /// @notice Returns the number of quotes requested by an account, including executed or expired quotes.
    function quoteCountOf(address user) external view returns (uint256) {
        return _quoteIds[user].length;
    }

    /// @notice Returns this desk's balance of either supported token in six-decimal base units.
    function inventory(address token) external view returns (uint256) {
        return _supportedToken(token).balanceOf(address(this));
    }

    /// @dev Resolves a supported inventory token, rejecting every other address.
    function _supportedToken(address token) private view returns (IERC20) {
        if (token != address(usdc) && token != address(eurc)) revert UnsupportedToken(token);
        return IERC20(token);
    }
}
