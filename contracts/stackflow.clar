;; Title: StacksFlow Commerce Hub
;; Summary: Enterprise-grade Bitcoin payment processing infrastructure enabling seamless sBTC transactions with automated fee distribution, 
;; merchant management, and real-time settlement capabilities  
;; Description: StacksFlow Commerce Hub revolutionizes digital commerce by providing a comprehensive payment gateway solution built on the Stacks blockchain. 
;; This smart contract empowers businesses to accept sBTC payments with enterprise-level features including automated invoice generation, multi-tier fee structures,
;; instant settlement processing, and comprehensive merchant dashboard capabilities. The platform supports complex business workflows through webhook integrations,
;; reference-based transaction tracking, and built-in refund mechanisms, while maintaining robust security through time-locked payments and balance segregation.

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_PAYMENT_NOT_FOUND (err u102))
(define-constant ERR_PAYMENT_ALREADY_PROCESSED (err u103))
(define-constant ERR_PAYMENT_EXPIRED (err u104))
(define-constant ERR_INSUFFICIENT_BALANCE (err u105))
(define-constant ERR_BUSINESS_NOT_REGISTERED (err u106))
(define-constant ERR_INVALID_SIGNATURE (err u107))

;; Data Variables
(define-data-var next-payment-id uint u1)
(define-data-var platform-fee-basis-points uint u100) ;; 1% platform fee
(define-data-var fee-collector principal CONTRACT_OWNER)

;; Data Maps
(define-map businesses
  principal
  {
    name: (string-ascii 64),
    webhook-url: (optional (string-ascii 256)),
    fee-rate: uint, ;; basis points (e.g., 250 = 2.5%)
    is-active: bool,
    total-processed: uint,
    registration-block: uint,
  }
)

(define-map payments
  uint
  {
    business: principal,
    customer: (optional principal),
    amount: uint,
    description: (string-ascii 256),
    reference-id: (string-ascii 64),
    status: (string-ascii 16), ;; "pending", "completed", "expired", "refunded"
    created-at: uint,
    expires-at: uint,
    processed-at: (optional uint),
    processor: (optional principal),
  }
)

(define-map payment-references
  {
    business: principal,
    reference: (string-ascii 64),
  }
  uint
)

(define-map business-balances
  principal
  uint
)

;; Public Functions

;; Register a new business
(define-public (register-business
    (name (string-ascii 64))
    (webhook-url (optional (string-ascii 256)))
  )
  (let ((caller tx-sender))
    (asserts! (is-none (map-get? businesses caller)) ERR_UNAUTHORIZED)
    (asserts! (> (len name) u0) ERR_INVALID_AMOUNT)
    ;; Name cannot be empty
    (asserts! (<= (len name) u64) ERR_INVALID_AMOUNT)
    ;; Name length check
    (map-set businesses caller {
      name: name,
      webhook-url: webhook-url,
      fee-rate: u0, ;; Default 0% business fee
      is-active: true,
      total-processed: u0,
      registration-block: stacks-block-height,
    })
    (ok true)
  )
)

;; Update business settings
(define-public (update-business
    (name (string-ascii 64))
    (webhook-url (optional (string-ascii 256)))
    (fee-rate uint)
  )
  (let (
      (caller tx-sender)
      (current-business (unwrap! (map-get? businesses caller) ERR_BUSINESS_NOT_REGISTERED))
    )
    (asserts! (< fee-rate u1000) ERR_INVALID_AMOUNT)
    ;; Max 10% fee
    (asserts! (> (len name) u0) ERR_INVALID_AMOUNT)
    ;; Name cannot be empty
    (asserts! (<= (len name) u64) ERR_INVALID_AMOUNT)
    ;; Name length check
    (map-set businesses caller
      (merge current-business {
        name: name,
        webhook-url: webhook-url,
        fee-rate: fee-rate,
      })
    )
    (ok true)
  )
)

;; Create a new payment request
(define-public (create-payment
    (amount uint)
    (description (string-ascii 256))
    (reference-id (string-ascii 64))
    (expires-in-blocks uint)
  )
  (let (
      (caller tx-sender)
      (payment-id (var-get next-payment-id))
      (current-block stacks-block-height)
      (expiry-block (+ current-block expires-in-blocks))
    )
    ;; Validation
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> expires-in-blocks u0) ERR_INVALID_AMOUNT)
    (asserts! (< expires-in-blocks u4320) ERR_INVALID_AMOUNT)
    ;; Max 30 days
    (asserts! (> (len description) u0) ERR_INVALID_AMOUNT)
    ;; Description cannot be empty
    (asserts! (<= (len description) u256) ERR_INVALID_AMOUNT)
    ;; Description length check
    (asserts! (> (len reference-id) u0) ERR_INVALID_AMOUNT)
    ;; Reference ID cannot be empty
    (asserts! (<= (len reference-id) u64) ERR_INVALID_AMOUNT)
    ;; Reference ID length check
    (asserts! (is-some (map-get? businesses caller)) ERR_BUSINESS_NOT_REGISTERED)
    (asserts!
      (is-none (map-get? payment-references {
        business: caller,
        reference: reference-id,
      }))
      ERR_PAYMENT_ALREADY_PROCESSED
    )

    ;; Create payment
    (map-set payments payment-id {
      business: caller,
      customer: none,
      amount: amount,
      description: description,
      reference-id: reference-id,
      status: "pending",
      created-at: current-block,
      expires-at: expiry-block,
      processed-at: none,
      processor: none,
    })

    ;; Set reference mapping
    (map-set payment-references {
      business: caller,
      reference: reference-id,
    }
      payment-id
    )

    ;; Increment payment ID
    (var-set next-payment-id (+ payment-id u1))

    (ok payment-id)
  )
)

;; Process payment - customer pays the invoice
(define-public (pay-invoice (payment-id uint))
  (let (
      (caller tx-sender)
      (payment (unwrap! (map-get? payments payment-id) ERR_PAYMENT_NOT_FOUND))
      (business-data (unwrap! (map-get? businesses (get business payment))
        ERR_BUSINESS_NOT_REGISTERED
      ))
      (current-block stacks-block-height)
    )
    ;; Validations
    (asserts! (is-eq (get status payment) "pending")
      ERR_PAYMENT_ALREADY_PROCESSED
    )
    (asserts! (< current-block (get expires-at payment)) ERR_PAYMENT_EXPIRED)
    (asserts! (get is-active business-data) ERR_UNAUTHORIZED)

    ;; Calculate fees
    (let (
        (payment-amount (get amount payment))
        (platform-fee (/ (* payment-amount (var-get platform-fee-basis-points)) u10000))
        (business-fee (/ (* payment-amount (get fee-rate business-data)) u10000))
        (total-fees (+ platform-fee business-fee))
        (net-amount (- payment-amount total-fees))
      )
      ;; Transfer sBTC from customer to contract
      (try! (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
        transfer payment-amount caller (as-contract tx-sender) none
      ))

      ;; Update business balance
      (let ((current-balance (default-to u0 (map-get? business-balances (get business payment)))))
        (map-set business-balances (get business payment)
          (+ current-balance net-amount)
        )
      )

      ;; Transfer platform fee to fee collector
      (if (> platform-fee u0)
        (try! (as-contract (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
          transfer platform-fee tx-sender (var-get fee-collector) none
        )))
        true
      )

      ;; Update payment status
      (map-set payments payment-id
        (merge payment {
          customer: (some caller),
          status: "completed",
          processed-at: (some current-block),
          processor: (some caller),
        })
      )

      ;; Update business stats
      (map-set businesses (get business payment)
        (merge business-data { total-processed: (+ (get total-processed business-data) payment-amount) })
      )

      (ok {
        payment-id: payment-id,
        net-amount: net-amount,
        fees: total-fees,
      })
    )
  )
)

;; Business withdraws accumulated balance
(define-public (withdraw-balance (amount uint))
  (let (
      (caller tx-sender)
      (current-balance (default-to u0 (map-get? business-balances caller)))
    )
    (asserts! (is-some (map-get? businesses caller)) ERR_BUSINESS_NOT_REGISTERED)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)

    ;; Update balance
    (map-set business-balances caller (- current-balance amount))

    ;; Transfer sBTC to business
    (try! (as-contract (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
      transfer amount tx-sender caller none
    )))

    (ok amount)
  )
)

;; Refund a payment (business only)
(define-public (refund-payment (payment-id uint))
  (let (
      (caller tx-sender)
      (payment (unwrap! (map-get? payments payment-id) ERR_PAYMENT_NOT_FOUND))
      (customer (unwrap! (get customer payment) ERR_PAYMENT_NOT_FOUND))
    )
    (asserts! (is-eq caller (get business payment)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status payment) "completed")
      ERR_PAYMENT_ALREADY_PROCESSED
    )

    (let (
        (refund-amount (get amount payment))
        (current-balance (default-to u0 (map-get? business-balances caller)))
      )
      (asserts! (>= current-balance refund-amount) ERR_INSUFFICIENT_BALANCE)

      ;; Deduct from business balance
      (map-set business-balances caller (- current-balance refund-amount))

      ;; Transfer back to customer
      (try! (as-contract (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
        transfer refund-amount tx-sender customer none
      )))

      ;; Update payment status
      (map-set payments payment-id
        (merge payment {
          status: "refunded",
          processed-at: (some stacks-block-height),
        })
      )

      (ok refund-amount)
    )
  )
)

;; Admin function to update platform fee
(define-public (set-platform-fee (new-fee-basis-points uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-fee-basis-points u1000) ERR_INVALID_AMOUNT) ;; Max 10%
    (var-set platform-fee-basis-points new-fee-basis-points)
    (ok true)
  )
)

;; Admin function to update fee collector
(define-public (set-fee-collector (new-collector principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Basic validation that the new collector is not the zero address
    (asserts! (not (is-eq new-collector 'SP000000000000000000002Q6VF78))
      ERR_INVALID_AMOUNT
    )
    (var-set fee-collector new-collector)
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-payment (payment-id uint))
  (map-get? payments payment-id)
)

(define-read-only (get-payment-by-reference
    (business principal)
    (reference (string-ascii 64))
  )
  (let ((payment-id (map-get? payment-references {
      business: business,
      reference: reference,
    })))
    (match payment-id
      id (map-get? payments id)
      none
    )
  )
)

(define-read-only (get-business (business-principal principal))
  (map-get? businesses business-principal)
)

(define-read-only (get-business-balance (business-principal principal))
  (default-to u0 (map-get? business-balances business-principal))
)

(define-read-only (get-platform-fee)
  (var-get platform-fee-basis-points)
)

(define-read-only (get-fee-collector)
  (var-get fee-collector)
)

(define-read-only (calculate-fees
    (amount uint)
    (business-fee-rate uint)
  )
  (let (
      (platform-fee (/ (* amount (var-get platform-fee-basis-points)) u10000))
      (business-fee (/ (* amount business-fee-rate) u10000))
    )
    {
      platform-fee: platform-fee,
      business-fee: business-fee,
      total-fees: (+ platform-fee business-fee),
      net-amount: (- amount (+ platform-fee business-fee)),
    }
  )
)

(define-read-only (is-payment-valid (payment-id uint))
  (match (map-get? payments payment-id)
    payment (and
      (is-eq (get status payment) "pending")
      (< stacks-block-height (get expires-at payment))
    )
    false
  )
)

(define-read-only (get-next-payment-id)
  (var-get next-payment-id)
)