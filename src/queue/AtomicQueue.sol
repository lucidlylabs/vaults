// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableRoles} from "../../lib/solady/src/auth/OwnableRoles.sol";
import {ReentrancyGuard} from "../../lib/solady/src/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "../../lib/solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "../../lib/solady/src/utils/SafeTransferLib.sol";
import {ERC20} from "../../lib/solady/src/tokens/ERC20.sol";
import {IRateProvider} from "../RateProvider/IRateProvider.sol";
import {RateProviderRepository} from "../RateProvider/RateProviderRepository.sol";
import {IAtomicSolver} from "./IAtomicSolver.sol";

contract AtomicQueue is OwnableRoles, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            TYPES                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    ///  @notice Stores request information needed to fulfill a users atomic
    ///          request.
    ///  @param deadline unix timestamp for when request is no longer valid
    ///  @param atomicPrice the price in terms of `want` asset the user wants
    ///         their `offer` assets "sold" at
    ///  @dev atomicPrice MUST be in terms of `want` asset decimals.
    ///  @param offerAmount the amount of `offer` asset the user wants
    ///         converted to `want` asset
    ///  @param inSolve bool used during solves to prevent duplicate users
    ///         and to prevent redoing multiple checks
    struct AtomicRequest {
        /// @dev deadline to fulfill the request
        uint64 deadline;
        /// @dev in terms of want asset decimals
        uint88 atomicPrice;
        /// @dev in terms of sell asset decimals
        uint96 offerAmount;
        /// @dev bool to check if this order is being fullfilled
        bool inSolve;
    }

    /// @notice Used in `viewSolveMetaData` helper function to return data in
    ///         a clean struct
    /// @param user address of the user
    /// @param flags 8 bits indicating the state of the user only the first 4
    ///        bits are used XXXX0000 either all flags are false(user is
    ///        solvable) or only 1 is true(an error occurred).
    ///        from right to left
    ///        - 0: indicates user deadline has passed.
    ///        - 1: indicates user request has zero offer amount.
    ///        - 2: indicates user does not have enough offer asset in wallet.
    ///        - 3: indicates user has not given AtomicQueue approval.
    /// @param assetsToOffer
    /// @param assetsForWant
    struct SolveMetaData {
        address user;
        uint8 flags;
        uint256 assetsToOffer;
        uint256 assetsForWant;
    }

    /// @notice Used in `viewVerboseSolveMetaData` helper function to return
    ///         data in a clean struct.
    /// @param user the address of the user
    /// @param deadlineExceeded indicates if the user has passed their deadline
    /// @param zeroOfferAmount indicates if the user has a zero offer amount
    /// @param insufficientOfferBalance indicates if the user has insufficient offer balance
    /// @param insufficientOfferAllowance indicates if the user has insufficient offer allowance
    /// @param assetsToOffer the amount of offer asset to solve
    /// @param assetsForWant the amount of assets users want for their offer assets
    struct VerboseSolveMetaData {
        address user;
        bool deadlineExceeded;
        bool zeroOfferAmount;
        bool insufficientOfferBalance;
        bool insufficientOfferAllowance;
        uint256 assetsToOffer;
        uint256 assetsForWant;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          CONSTANTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 public constant MAX_DISCOUNT = 0.01e6;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    mapping(address => mapping(ERC20 => mapping(ERC20 => AtomicRequest))) public userAtomicRequest;
    bool public isPaused;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error AtomicQueue__UserRepeated(address user);
    error AtomicQueue__RequestDeadlineExceeded(address user);
    error AtomicQueue__UserNotInSolve(address user);
    error AtomicQueue__ZeroOfferAmount(address user);
    error AtomicQueue__SafeRequestOfferAmountGreaterThanOfferBalance(uint256 offerAmount, uint256 offerBalance);
    error AtomicQueue__SafeRequestDeadlineExceeded(uint256 deadline);
    error AtomicQueue__SafeRequestInsufficientOfferAllowance(uint256 offerAmount, uint256 offerAllowance);
    error AtomicQueue__SafeRequestOfferAmountZero();
    error AtomicQueue__SafeRequestDiscountTooLarge();
    error AtomicQueue__SafeRequestOfferMismatch();
    error AtomicQueue__SafeRequestCannotCastToUint88();
    error AtomicQueue__Paused();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event AtomicRequestUpdated(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );

    event AtomicRequestFulfilled(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 offerAmountSpent,
        uint256 wantAmountReceived,
        uint256 timestamp
    );
    event Paused();
    event Unpaused();

    constructor(address owner_) {
        _initializeOwner(owner_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                             AUTH                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 constant ROLE_QUEUE_OWNER = uint256(keccak256("ROLE_QUEUE_OWNER"));
    uint256 constant ROLE_SOLVER = uint256(keccak256("ROLE_SOLVER"));

    modifier onlyQueueOwner() {
        _checkRoles(ROLE_QUEUE_OWNER);
        _;
    }

    modifier onlySolver() {
        _checkRoles(ROLE_QUEUE_OWNER | ROLE_SOLVER);
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice pause this contract which stops solving and updating user requests
    function pause() external onlyQueueOwner {
        isPaused = true;
        emit Paused();
    }

    /// @notice unpause this contract
    function unpause() external onlyQueueOwner {
        isPaused = false;
        emit Unpaused();
    }

    /// @notice getter function for users' atomic requests
    /// @param user address of the user
    /// @param offer the offer asset
    /// @param want the want assset
    function getUserAtomicRequest(address user, ERC20 offer, ERC20 want) external view returns (AtomicRequest memory) {
        return userAtomicRequest[user][offer][want];
    }

    /// @notice getter function to check validity of user requests
    /// @param offer sell asset
    /// @param user address of the user making the request
    /// @param userRequest the request struct to validate
    function isAtomicRequestValid(ERC20 offer, address user, AtomicRequest calldata userRequest)
        external
        view
        returns (bool)
    {
        if (userRequest.offerAmount > offer.balanceOf(user)) return false;
        if (block.timestamp > userRequest.deadline) return false;
        if (offer.allowance(user, address(this)) < userRequest.offerAmount) return false;
        if (userRequest.offerAmount == 0) return false;
        if (userRequest.atomicPrice == 0) return false;

        return true;
    }

    /// @notice allows users to add/update their withdraw request.
    /// @dev It is possible for a withdraw request with a zero atomicPrice to
    ///      be made, and solved. If this happens, users will be selling
    ///      their shares for no assets in return. To determine a safe
    ///      atomicPrice,`share.previewRedeem` should be used to get a good
    ///      share price, then the user can lower it from there to make their
    ///      request fill faster.
    /// @param offer the offer asset
    /// @param want the want assset
    /// @param userRequest new request
    function updateAtomicRequest(ERC20 offer, ERC20 want, AtomicRequest memory userRequest)
        external
        nonReentrant
        onlyOwner
    {
        _updateAtomicRequest(offer, want, userRequest);
    }

    /// @notice mostly identical to `updateAtomicRequest` but with additional
    ///         checks to ensure the request is safe. Adds in RateProvider and
    ///         discount to calculate a safe atomicPrice.
    /// @dev this function will completely ignore the provided atomic price
    ///      and calculate a new one based off the the accountant rate in
    ///      quote and the discount provided.
    /// @param offer the offer asset
    /// @param want the want asset
    /// @param userRequest new request
    /// @param rateProviderRepo repository contract to fetch rate provider information
    /// @param discount the discount to apply to the rate in quote
    function safeUpdateAtomicRequest(
        ERC20 offer,
        ERC20 want,
        AtomicRequest memory userRequest,
        RateProviderRepository rateProviderRepo,
        uint256 discount
    ) external nonReentrant {
        uint256 offerBalance = offer.balanceOf(msg.sender);
        if (userRequest.offerAmount > offerBalance) {
            revert AtomicQueue__SafeRequestOfferAmountGreaterThanOfferBalance(userRequest.offerAmount, offerBalance);
        }
        if (block.timestamp > userRequest.deadline) {
            revert AtomicQueue__SafeRequestDeadlineExceeded(userRequest.deadline);
        }
        uint256 offerAllowance = offer.allowance(msg.sender, address(this));
        if (offerAllowance < userRequest.offerAmount) {
            revert AtomicQueue__SafeRequestInsufficientOfferAllowance(userRequest.offerAmount, offerAllowance);
        }
        if (userRequest.offerAmount == 0) revert AtomicQueue__SafeRequestOfferAmountZero();
        if (discount > MAX_DISCOUNT) revert AtomicQueue__SafeRequestDiscountTooLarge();

        if (address(offer) != address(rateProviderRepo.vault())) revert AtomicQueue__SafeRequestOfferMismatch();
        uint256 safeRate = rateProviderRepo.getVaultSharePriceInAsset(address(want));
        uint256 safeAtomicPrice = FixedPointMathLib.mulDiv(safeRate, 1e6 - discount, 1e6);
        if (safeAtomicPrice > type(uint8).max) revert AtomicQueue__SafeRequestCannotCastToUint88();
        userRequest.atomicPrice = uint88(safeAtomicPrice);
        _updateAtomicRequest(offer, want, userRequest);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      SOLVER FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice called by solvers in order to exchange offer asset for want
    ///         asset.
    ///         solvers are optimistically transferred the offer asset, then
    ///         are required to approve this contract to spend enough of want
    ///         assets to cover all requests
    /// @dev it is very likely `solve` txs will be front run if broadcasted to
    ///      public mempools, so solvers should use private mempools.
    /// @param offer the ERC20 offer token to solve for
    /// @param want the ERC20 want token to solve for
    /// @param users an array of user addresses to solve for
    /// @param runData extra data that is passed back to solver when
    ///        `finishSolve` is called
    /// @param solver the address to make `finishSolve` callback to
    function solve(ERC20 offer, ERC20 want, address[] calldata users, bytes calldata runData, address solver)
        external
        nonReentrant
        onlySolver
    {
        if (isPaused) revert AtomicQueue__Paused();

        // Save offer asset decimals.
        uint8 offerDecimals = offer.decimals();

        uint256 assetsToOffer;
        uint256 assetsForWant;
        for (uint256 i; i < users.length; ++i) {
            AtomicRequest storage request = userAtomicRequest[users[i]][offer][want];

            if (request.inSolve) revert AtomicQueue__UserRepeated(users[i]);
            if (block.timestamp > request.deadline) revert AtomicQueue__RequestDeadlineExceeded(users[i]);
            if (request.offerAmount == 0) revert AtomicQueue__ZeroOfferAmount(users[i]);

            // User gets whatever their atomic price * offerAmount is.
            assetsForWant += _calculateAssetAmount(request.offerAmount, request.atomicPrice, offerDecimals);

            // If all checks above passed, the users request is valid and should be fulfilled.
            assetsToOffer += request.offerAmount;
            request.inSolve = true;
            // Transfer shares from user to solver.
            SafeTransferLib.safeTransferFrom(address(offer), users[i], solver, request.offerAmount);
        }

        IAtomicSolver(solver).finishSolve(runData, msg.sender, offer, want, assetsToOffer, assetsForWant);

        for (uint256 i; i < users.length; ++i) {
            AtomicRequest storage request = userAtomicRequest[users[i]][offer][want];

            if (request.inSolve) {
                // We know that the minimum price and deadline arguments are satisfied since this can only be true if they were.

                // Send user their share of assets.
                uint256 assetsToUser = _calculateAssetAmount(request.offerAmount, request.atomicPrice, offerDecimals);

                SafeTransferLib.safeTransferFrom(address(want), solver, users[i], assetsToUser);

                emit AtomicRequestFulfilled(
                    users[i], address(offer), address(want), request.offerAmount, assetsToUser, block.timestamp
                );

                // Set shares to withdraw to 0.
                request.offerAmount = 0;
                request.inSolve = false;
            } else {
                revert AtomicQueue__UserNotInSolve(users[i]);
            }
        }
    }

    /// @notice helper function solvers can use to determine if users are
    ///         solvable, and the required amounts to do so.
    ///         repeated users are not accounted for in this setup, so if
    ///         solvers have repeat users in their `users`
    ///         array the results can be wrong.
    /// @dev Since a user can have multiple requests with the same offer asset
    ///      but different want asset, it is
    ///      possible for `viewSolveMetaData` to report no errors, but for a
    ///      solve to fail, if any solves were done
    ///      between the time `viewSolveMetaData` and before `solve` is called.
    /// @param offer the ERC20 offer token to check for solvability
    /// @param want the ERC20 want token to check for solvability
    /// @param users an array of user addresses to check for solvability
    function viewSolveMetaData(ERC20 offer, ERC20 want, address[] calldata users)
        external
        view
        returns (SolveMetaData[] memory metaData, uint256 totalAssetsForWant, uint256 totalAssetsToOffer)
    {
        // Save offer asset decimals.
        uint8 offerDecimals = offer.decimals();

        // Setup meta data.
        metaData = new SolveMetaData[](users.length);

        for (uint256 i; i < users.length; ++i) {
            AtomicRequest memory request = userAtomicRequest[users[i]][offer][want];

            metaData[i].user = users[i];

            if (block.timestamp > request.deadline) {
                metaData[i].flags |= uint8(1);
            }
            if (request.offerAmount == 0) {
                metaData[i].flags |= uint8(1) << 1;
            }
            if (offer.balanceOf(users[i]) < request.offerAmount) {
                metaData[i].flags |= uint8(1) << 2;
            }
            if (offer.allowance(users[i], address(this)) < request.offerAmount) {
                metaData[i].flags |= uint8(1) << 3;
            }

            metaData[i].assetsToOffer = request.offerAmount;

            // User gets whatever their execution share price is.
            uint256 userAssets = _calculateAssetAmount(request.offerAmount, request.atomicPrice, offerDecimals);
            metaData[i].assetsForWant = userAssets;

            // If flags is zero, no errors occurred.
            if (metaData[i].flags == 0) {
                totalAssetsForWant += userAssets;
                totalAssetsToOffer += request.offerAmount;
            }
        }
    }

    /// @notice helper function solvers can use to determine if users are
    ///         solvable, and the required amounts to do so.
    ///         repeated users are not accounted for in this setup, so if
    ///         solvers have repeat users in their `users`
    ///         array the results can be wrong.
    /// @dev since a user can have multiple requests with the same offer asset
    ///      but different want asset, it is possible for `viewSolveMetaData`
    ///      to report no errors, but for a solve to fail, if any solves were
    ///      done between the time `viewSolveMetaData` and before `solve` is
    ///      called.
    /// @param offer the ERC20 offer token to check for solvability
    /// @param want the ERC20 want token to check for solvability
    /// @param users an array of user addresses to check for solvability
    function viewVerboseSolveMetaData(ERC20 offer, ERC20 want, address[] calldata users)
        external
        view
        returns (VerboseSolveMetaData[] memory metaData, uint256 totalAssetsForWant, uint256 totalAssetsToOffer)
    {
        // Save offer asset decimals.
        uint8 offerDecimals = offer.decimals();

        // Setup meta data.
        metaData = new VerboseSolveMetaData[](users.length);

        for (uint256 i; i < users.length; ++i) {
            AtomicRequest memory request = userAtomicRequest[users[i]][offer][want];

            metaData[i].user = users[i];

            if (block.timestamp > request.deadline) {
                metaData[i].deadlineExceeded = true;
            }
            if (request.offerAmount == 0) {
                metaData[i].zeroOfferAmount = true;
            }
            if (offer.balanceOf(users[i]) < request.offerAmount) {
                metaData[i].insufficientOfferBalance = true;
            }
            if (offer.allowance(users[i], address(this)) < request.offerAmount) {
                metaData[i].insufficientOfferAllowance = true;
            }

            metaData[i].assetsToOffer = request.offerAmount;

            // User gets whatever their execution share price is.
            uint256 userAssets = _calculateAssetAmount(request.offerAmount, request.atomicPrice, offerDecimals);
            metaData[i].assetsForWant = userAssets;

            // If flags is zero, no errors occurred.
            if (
                !metaData[i].deadlineExceeded && !metaData[i].zeroOfferAmount && !metaData[i].insufficientOfferBalance
                    && !metaData[i].insufficientOfferAllowance
            ) {
                totalAssetsForWant += userAssets;
                totalAssetsToOffer += request.offerAmount;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice allows user to add/update their withdraw request.
    /// @notice it is possible for a withdraw request with a zero atomicprice
    ///         to be made, and solved
    ///         if this happens, users will be selling their shares for no
    ///         assets in return.
    ///         to determine a safe atomicPrice, share.previewRedeem should be
    ///         used to get a good share price, then the user can lower it from
    ///         there to make their request fill faster.
    /// @param offer asset offered
    /// @param want asset wanted
    /// @param userRequest the users request
    function _updateAtomicRequest(ERC20 offer, ERC20 want, AtomicRequest memory userRequest) internal {
        if (isPaused) revert AtomicQueue__Paused();
        AtomicRequest storage request = userAtomicRequest[msg.sender][offer][want];

        request.deadline = userRequest.deadline;
        request.atomicPrice = userRequest.atomicPrice;
        request.offerAmount = userRequest.offerAmount;

        // Emit full amount user has.
        emit AtomicRequestUpdated(
            msg.sender,
            address(offer),
            address(want),
            userRequest.offerAmount,
            userRequest.deadline,
            userRequest.atomicPrice,
            block.timestamp
        );
    }

    /// @notice helper function to calculate the amount of want assets a users
    ///         wants in exchange for `offerAmount` of offer asset.
    function _calculateAssetAmount(uint256 offerAmount, uint256 atomicPrice, uint8 offerDecimals)
        internal
        pure
        returns (uint256)
    {
        return FixedPointMathLib.mulDiv(atomicPrice, offerAmount, 10 ** offerDecimals);
    }
}
