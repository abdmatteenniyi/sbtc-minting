;; sbtc-minting.clar
;; A minimal Bitcoin-collateralized stablecoin protocol on Stacks (MVP version)

(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_UNDERCOLLATERALIZED (err u103))
(define-constant ERR_VAULT_NOT_FOUND (err u104))
(define-constant ERR_DIVISION_BY_ZERO (err u105))
(define-constant COLLATERAL_RATIO u150) ;; 150% overcollateralized

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; ===== Token Interface (SIP-010) =====
(define-trait sip010-token-standard
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; ===== Data Maps =====

(define-data-var btc-price uint u0) ;; BTC/USD oracle feed (e.g. 60_000 = $60,000)

(define-map user-vault
  principal
  {
    collateral: uint,
    debt: uint
  }
)

;; ===== Admin Functions =====

(define-public (set-btc-price (price uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set btc-price price)
    (ok price)
  )
)

(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok new-owner)
  )
)

;; ===== Helper Functions =====

(define-read-only (get-collateral-ratio (collateral uint) (debt uint))
  (if (is-eq debt u0)
      (ok u9999) ;; Very high ratio if no debt
      (let (
            (price (var-get btc-price))
            (value (* collateral price))
           )
        (if (is-eq debt u0)
            ERR_DIVISION_BY_ZERO
            (ok (/ (* value u100) debt))
        )
      )
  )
)

;; ===== Public Functions =====

(define-public (lock-and-mint (collateral uint) (mint-amount uint))
  (let (
        (vault (default-to {collateral: u0, debt: u0} (map-get? user-vault tx-sender)))
        (price (var-get btc-price))
        (required-collateral (/ (* mint-amount COLLATERAL_RATIO) u100))
        (collateral-value (* collateral price))
       )
    (asserts! (> price u0) ERR_INVALID_AMOUNT)
    (asserts! (> collateral u0) ERR_INVALID_AMOUNT)
    (asserts! (> mint-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= collateral-value required-collateral) ERR_INSUFFICIENT_COLLATERAL)
    
    ;; Update vault
    (map-set user-vault tx-sender
      {
        collateral: (+ collateral (get collateral vault)),
        debt: (+ mint-amount (get debt vault))
      }
    )
    ;; Return success (token minting would be handled by separate token contract)
    (ok mint-amount)
  )
)

(define-public (burn-and-unlock (burn-amount uint))
  (let (
        (vault-option (map-get? user-vault tx-sender))
       )
    (match vault-option
      vault
      (let (
            (current-debt (get debt vault))
            (current-collateral (get collateral vault))
            (new-debt (if (>= burn-amount current-debt) u0 (- current-debt burn-amount)))
            (price (var-get btc-price))
           )
        (asserts! (<= burn-amount current-debt) ERR_INVALID_AMOUNT)
        (asserts! (> price u0) ERR_INVALID_AMOUNT)
        
        (let (
              (unlockable-btc (if (is-eq new-debt u0) 
                                current-collateral
                                (let (
                                      (min-required (/ (* new-debt COLLATERAL_RATIO) u100))
                                      (min-btc (/ min-required price))
                                     )
                                  (if (> current-collateral min-btc)
                                    (- current-collateral min-btc)
                                    u0))))
             )
          ;; Update vault
          (map-set user-vault tx-sender
            {
              collateral: (- current-collateral unlockable-btc),
              debt: new-debt
            }
          )
          ;; Return BTC amount that can be unlocked
          (ok unlockable-btc)
        )
      )
      ERR_VAULT_NOT_FOUND
    )
  )
)

(define-public (liquidate (target principal))
  (let (
        (vault-option (map-get? user-vault target))
       )
    (match vault-option
      vault
      (let (
            (collateral (get collateral vault))
            (debt (get debt vault))
           )
        (match (get-collateral-ratio collateral debt)
          ok-ratio
          (begin
            (asserts! (< ok-ratio COLLATERAL_RATIO) ERR_UNDERCOLLATERALIZED)
            ;; Delete vault (liquidation)
            (map-delete user-vault target)
            ;; Return collateral to liquidator
            (ok collateral)
          )
          err-code
          (err err-code)
        )
      )
      ERR_VAULT_NOT_FOUND
    )
  )
)

;; ===== View Functions =====

(define-read-only (get-user-vault (user principal))
  (default-to {collateral: u0, debt: u0} (map-get? user-vault user))
)

(define-read-only (get-btc-price) 
  (ok (var-get btc-price))
)

(define-read-only (get-contract-owner)
  (ok (var-get contract-owner))
)

(define-read-only (calculate-max-mint (collateral uint))
  (let (
        (price (var-get btc-price))
        (collateral-value (* collateral price))
       )
    (if (> price u0)
        (ok (/ (* collateral-value u100) COLLATERAL_RATIO))
        (ok u0)
    )
  )
)

(define-read-only (is-vault-safe (user principal))
  (let (
        (vault (get-user-vault user))
        (collateral (get collateral vault))
        (debt (get debt vault))
       )
    (if (is-eq debt u0)
        (ok true)
        (match (get-collateral-ratio collateral debt)
          ok-ratio (ok (>= ok-ratio COLLATERAL_RATIO))
          err-code (ok false)
        )
    )
  )
)