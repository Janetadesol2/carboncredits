;; Carbon Credits - Tokenized Carbon Offset Marketplace
;; Features: Project verification, credit tokenization, automated retirement, impact tracking

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-project-not-found (err u101))
(define-constant err-insufficient-credits (err u102))
(define-constant err-already-verified (err u103))
(define-constant err-not-verified (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-project-expired (err u106))
(define-constant err-already-retired (err u107))
(define-constant err-max-supply (err u108))
(define-constant err-invalid-vintage (err u109))
(define-constant err-paused (err u110))
(define-constant err-below-minimum (err u111))
(define-constant err-duplicate (err u112))

;; Protocol Parameters
(define-constant credits-per-ton u1000) ;; 1000 credits = 1 ton CO2
(define-constant verification-fee u10000000) ;; 10 STX verification fee
(define-constant marketplace-fee u250) ;; 2.5% marketplace fee
(define-constant retirement-bonus u100) ;; 1% bonus for retirement
(define-constant min-credits-purchase u100) ;; Minimum 0.1 ton
(define-constant max-credits-per-project u1000000000) ;; 1M tons max
(define-constant verification-period u4320) ;; ~30 days for verification
(define-constant project-validity-years u5) ;; Projects valid for 5 years
(define-constant validator-threshold u3) ;; 3 validators needed

;; Data Variables
(define-data-var project-counter uint u0)
(define-data-var total-credits-issued uint u0)
(define-data-var total-credits-retired uint u0)
(define-data-var marketplace-volume uint u0)
(define-data-var platform-fees-collected uint u0)
(define-data-var active-validators uint u0)
(define-data-var platform-paused bool false)

;; Data Maps
(define-map carbon-projects
    uint ;; project-id
    {
        name: (string-ascii 100),
        description: (string-ascii 500),
        location: (string-ascii 100),
        project-type: (string-ascii 50),
        owner: principal,
        credits-available: uint,
        credits-issued: uint,
        credits-retired: uint,
        price-per-credit: uint,
        vintage-year: uint,
        verification-status: (string-ascii 20),
        validator-count: uint,
        created-at: uint,
        expires-at: uint,
        metadata-uri: (string-ascii 256),
        is-active: bool
    })

(define-map credit-balances
    { owner: principal, project-id: uint }
    {
        balance: uint,
        purchased-at: uint,
        average-price: uint,
        retired: uint
    })

(define-map retirement-certificates
    uint ;; certificate-id
    {
        retiree: principal,
        project-id: uint,
        credits-retired: uint,
        retired-at: uint,
        beneficiary: (string-ascii 100),
        reason: (string-ascii 200),
        certificate-uri: (string-ascii 256)
    })

(define-map project-validators
    { project-id: uint, validator: principal }
    {
        validated: bool,
        validated-at: uint,
        validation-score: uint,
        comments: (string-ascii 500)
    })

(define-map verified-validators
    principal
    {
        is-active: bool,
        total-validated: uint,
        reputation-score: uint,
        registered-at: uint
    })

(define-map marketplace-listings
    { project-id: uint, seller: principal }
    {
        credits-for-sale: uint,
        price-per-credit: uint,
        listed-at: uint,
        is-active: bool
    })

(define-map impact-metrics
    uint ;; project-id
    {
        co2-sequestered: uint,
        trees-planted: uint,
        hectares-protected: uint,
        communities-benefited: uint,
        biodiversity-score: uint,
        water-saved: uint,
        last-updated: uint
    })

(define-map user-impact
    principal
    {
        total-offset: uint,
        projects-supported: uint,
        certificates-earned: uint,
        impact-score: uint,
        member-since: uint
    })

(define-map project-categories
    (string-ascii 50)
    {
        total-projects: uint,
        total-credits: uint,
        average-price: uint
    })

;; Private Functions
(define-private (calculate-marketplace-fee (amount uint))
    (/ (* amount marketplace-fee) u10000))

(define-private (calculate-impact-score (offset uint) (projects uint))
    (+ (/ offset u1000) (* projects u10)))

(define-private (is-project-valid (project-id uint))
    (match (map-get? carbon-projects project-id)
        project (and (get is-active project)
                    (< burn-block-height (get expires-at project))
                    (is-eq (get verification-status project) "verified"))
        false))

(define-private (update-user-impact (user principal) (credits uint) (project-id uint))
    (match (map-get? user-impact user)
        impact (map-set user-impact user
                      (merge impact {
                          total-offset: (+ (get total-offset impact) credits),
                          projects-supported: (+ (get projects-supported impact) u1),
                          impact-score: (calculate-impact-score 
                                       (+ (get total-offset impact) credits)
                                       (+ (get projects-supported impact) u1))
                      }))
        (map-set user-impact user {
            total-offset: credits,
            projects-supported: u1,
            certificates-earned: u0,
            impact-score: (calculate-impact-score credits u1),
            member-since: burn-block-height
        })))

(define-private (min-uint (a uint) (b uint))
    (if (<= a b) a b))

;; Read-only Functions
(define-read-only (get-project (project-id uint))
    (ok (map-get? carbon-projects project-id)))

(define-read-only (get-credit-balance (owner principal) (project-id uint))
    (ok (default-to { balance: u0, purchased-at: u0, average-price: u0, retired: u0 }
                   (map-get? credit-balances { owner: owner, project-id: project-id }))))

(define-read-only (get-retirement-certificate (certificate-id uint))
    (ok (map-get? retirement-certificates certificate-id)))

(define-read-only (get-user-impact (user principal))
    (ok (map-get? user-impact user)))

(define-read-only (get-project-metrics (project-id uint))
    (ok (map-get? impact-metrics project-id)))

(define-read-only (get-marketplace-listing (project-id uint) (seller principal))
    (ok (map-get? marketplace-listings { project-id: project-id, seller: seller })))

(define-read-only (calculate-carbon-offset (credits uint))
    (ok { tons-co2: (/ credits credits-per-ton),
          trees-equivalent: (/ credits u50),
          cars-offset-yearly: (/ credits u4500) }))

(define-read-only (get-platform-stats)
    (ok {
        total-projects: (var-get project-counter),
        credits-issued: (var-get total-credits-issued),
        credits-retired: (var-get total-credits-retired),
        marketplace-volume: (var-get marketplace-volume),
        platform-fees: (var-get platform-fees-collected)
    }))

;; Public Functions
(define-public (create-project (name (string-ascii 100))
                              (description (string-ascii 500))
                              (location (string-ascii 100))
                              (project-type (string-ascii 50))
                              (credits-available uint)
                              (price-per-credit uint)
                              (vintage-year uint)
                              (metadata-uri (string-ascii 256)))
    (let ((project-id (+ (var-get project-counter) u1))
          (expiry-block (+ burn-block-height (* u52560 project-validity-years))))
        
        ;; Validations
        (asserts! (not (var-get platform-paused)) err-paused)
        (asserts! (> credits-available u0) err-invalid-amount)
        (asserts! (<= credits-available max-credits-per-project) err-max-supply)
        (asserts! (> price-per-credit u0) err-invalid-amount)
        (asserts! (>= vintage-year u2020) err-invalid-vintage)
        
        ;; Pay verification fee
        (try! (stx-transfer? verification-fee tx-sender (as-contract tx-sender)))
        
        ;; Create project
        (map-set carbon-projects project-id {
            name: name,
            description: description,
            location: location,
            project-type: project-type,
            owner: tx-sender,
            credits-available: credits-available,
            credits-issued: u0,
            credits-retired: u0,
            price-per-credit: price-per-credit,
            vintage-year: vintage-year,
            verification-status: "pending",
            validator-count: u0,
            created-at: burn-block-height,
            expires-at: expiry-block,
            metadata-uri: metadata-uri,
            is-active: true
        })
        
        ;; Initialize impact metrics
        (map-set impact-metrics project-id {
            co2-sequestered: u0,
            trees-planted: u0,
            hectares-protected: u0,
            communities-benefited: u0,
            biodiversity-score: u0,
            water-saved: u0,
            last-updated: burn-block-height
        })
        
        ;; Update category stats
        (match (map-get? project-categories project-type)
            category (map-set project-categories project-type
                           (merge category {
                               total-projects: (+ (get total-projects category) u1),
                               total-credits: (+ (get total-credits category) credits-available)
                           }))
            (map-set project-categories project-type {
                total-projects: u1,
                total-credits: credits-available,
                average-price: price-per-credit
            }))
        
        ;; Update counter
        (var-set project-counter project-id)
        (var-set platform-fees-collected (+ (var-get platform-fees-collected) verification-fee))
        
        (ok project-id)))

(define-public (validate-project (project-id uint) (validation-score uint) (comments (string-ascii 500)))
    (let ((project (unwrap! (map-get? carbon-projects project-id) err-project-not-found))
          (validator-info (unwrap! (map-get? verified-validators tx-sender) err-unauthorized)))
        
        ;; Validations
        (asserts! (get is-active validator-info) err-unauthorized)
        (asserts! (is-eq (get verification-status project) "pending") err-already-verified)
        (asserts! (<= validation-score u100) err-invalid-amount)
        
        ;; Record validation
        (map-set project-validators 
                { project-id: project-id, validator: tx-sender }
                {
                    validated: true,
                    validated-at: burn-block-height,
                    validation-score: validation-score,
                    comments: comments
                })
        
        ;; Update project
        (let ((new-validator-count (+ (get validator-count project) u1)))
            (map-set carbon-projects project-id
                    (merge project {
                        validator-count: new-validator-count,
                        verification-status: (if (>= new-validator-count validator-threshold)
                                               "verified"
                                               "pending")
                    }))
            
            ;; Update validator stats
            (map-set verified-validators tx-sender
                    (merge validator-info {
                        total-validated: (+ (get total-validated validator-info) u1)
                    }))
            
            (ok (>= new-validator-count validator-threshold)))))

(define-public (purchase-credits (project-id uint) (credit-amount uint))
    (let ((project (unwrap! (map-get? carbon-projects project-id) err-project-not-found))
          (current-balance (default-to { balance: u0, purchased-at: u0, average-price: u0, retired: u0 }
                                      (map-get? credit-balances { owner: tx-sender, project-id: project-id }))))
        
        ;; Validations
        (asserts! (not (var-get platform-paused)) err-paused)
        (asserts! (is-project-valid project-id) err-not-verified)
        (asserts! (>= credit-amount min-credits-purchase) err-below-minimum)
        (asserts! (<= credit-amount (get credits-available project)) err-insufficient-credits)
        
        ;; Calculate payment
        (let ((total-cost (* credit-amount (get price-per-credit project)))
              (fee (calculate-marketplace-fee total-cost))
              (project-payment (- total-cost fee)))
            
            ;; Transfer payment
            (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
            
            ;; Transfer to project owner
            (try! (as-contract (stx-transfer? project-payment tx-sender (get owner project))))
            
            ;; Update credit balance
            (map-set credit-balances 
                    { owner: tx-sender, project-id: project-id }
                    {
                        balance: (+ (get balance current-balance) credit-amount),
                        purchased-at: burn-block-height,
                        average-price: (/ (+ (* (get balance current-balance) (get average-price current-balance))
                                           total-cost)
                                        (+ (get balance current-balance) credit-amount)),
                        retired: (get retired current-balance)
                    })
            
            ;; Update project
            (map-set carbon-projects project-id
                    (merge project {
                        credits-available: (- (get credits-available project) credit-amount),
                        credits-issued: (+ (get credits-issued project) credit-amount)
                    }))
            
            ;; Update user impact
            (update-user-impact tx-sender credit-amount project-id)
            
            ;; Update global stats
            (var-set total-credits-issued (+ (var-get total-credits-issued) credit-amount))
            (var-set marketplace-volume (+ (var-get marketplace-volume) total-cost))
            (var-set platform-fees-collected (+ (var-get platform-fees-collected) fee))
            
            (ok credit-amount))))

(define-public (retire-credits (project-id uint) (credit-amount uint) 
                              (beneficiary (string-ascii 100)) (reason (string-ascii 200)))
    (let ((balance-info (unwrap! (map-get? credit-balances { owner: tx-sender, project-id: project-id })
                                err-insufficient-credits))
          (project (unwrap! (map-get? carbon-projects project-id) err-project-not-found))
          (certificate-id (+ (var-get total-credits-retired) u1)))
        
        ;; Validations
        (asserts! (>= (get balance balance-info) credit-amount) err-insufficient-credits)
        (asserts! (> credit-amount u0) err-invalid-amount)
        
        ;; Create retirement certificate
        (map-set retirement-certificates certificate-id {
            retiree: tx-sender,
            project-id: project-id,
            credits-retired: credit-amount,
            retired-at: burn-block-height,
            beneficiary: beneficiary,
            reason: reason,
            certificate-uri: ""
        })
        
        ;; Update credit balance
        (map-set credit-balances 
                { owner: tx-sender, project-id: project-id }
                (merge balance-info {
                    balance: (- (get balance balance-info) credit-amount),
                    retired: (+ (get retired balance-info) credit-amount)
                }))
        
        ;; Update project
        (map-set carbon-projects project-id
                (merge project {
                    credits-retired: (+ (get credits-retired project) credit-amount)
                }))
        
        ;; Update user impact
        (match (map-get? user-impact tx-sender)
            impact (map-set user-impact tx-sender
                         (merge impact {
                             certificates-earned: (+ (get certificates-earned impact) u1)
                         }))
            true)
        
        ;; Give retirement bonus
        (let ((bonus (/ (* credit-amount retirement-bonus) u10000)))
            (and (> bonus u0)
                 (try! (as-contract (stx-transfer? bonus tx-sender tx-sender)))))
        
        ;; Update global stats
        (var-set total-credits-retired (+ (var-get total-credits-retired) credit-amount))
        
        (ok certificate-id)))

(define-public (list-credits-for-sale (project-id uint) (credit-amount uint) (price-per-credit uint))
    (let ((balance-info (unwrap! (map-get? credit-balances { owner: tx-sender, project-id: project-id })
                                err-insufficient-credits)))
        
        ;; Validations
        (asserts! (>= (get balance balance-info) credit-amount) err-insufficient-credits)
        (asserts! (> credit-amount u0) err-invalid-amount)
        (asserts! (> price-per-credit u0) err-invalid-amount)
        
        ;; Create or update listing
        (map-set marketplace-listings 
                { project-id: project-id, seller: tx-sender }
                {
                    credits-for-sale: credit-amount,
                    price-per-credit: price-per-credit,
                    listed-at: burn-block-height,
                    is-active: true
                })
        
        (ok true)))

(define-public (buy-from-marketplace (project-id uint) (seller principal) (credit-amount uint))
    (let ((listing (unwrap! (map-get? marketplace-listings { project-id: project-id, seller: seller })
                          err-project-not-found))
          (seller-balance (unwrap! (map-get? credit-balances { owner: seller, project-id: project-id })
                                 err-insufficient-credits))
          (buyer-balance (default-to { balance: u0, purchased-at: u0, average-price: u0, retired: u0 }
                                    (map-get? credit-balances { owner: tx-sender, project-id: project-id }))))
        
        ;; Validations
        (asserts! (get is-active listing) err-paused)
        (asserts! (<= credit-amount (get credits-for-sale listing)) err-insufficient-credits)
        (asserts! (<= credit-amount (get balance seller-balance)) err-insufficient-credits)
        
        ;; Calculate payment
        (let ((total-cost (* credit-amount (get price-per-credit listing)))
              (fee (calculate-marketplace-fee total-cost))
              (seller-payment (- total-cost fee)))
            
            ;; Transfer payment
            (try! (stx-transfer? total-cost tx-sender seller))
            
            ;; Platform fee
            (try! (stx-transfer? fee seller (as-contract tx-sender)))
            
            ;; Update balances
            (map-set credit-balances 
                    { owner: seller, project-id: project-id }
                    (merge seller-balance {
                        balance: (- (get balance seller-balance) credit-amount)
                    }))
            
            (map-set credit-balances 
                    { owner: tx-sender, project-id: project-id }
                    {
                        balance: (+ (get balance buyer-balance) credit-amount),
                        purchased-at: burn-block-height,
                        average-price: (get price-per-credit listing),
                        retired: (get retired buyer-balance)
                    })
            
            ;; Update listing
            (map-set marketplace-listings 
                    { project-id: project-id, seller: seller }
                    (merge listing {
                        credits-for-sale: (- (get credits-for-sale listing) credit-amount),
                        is-active: (> (- (get credits-for-sale listing) credit-amount) u0)
                    }))
            
            ;; Update stats
            (var-set marketplace-volume (+ (var-get marketplace-volume) total-cost))
            (var-set platform-fees-collected (+ (var-get platform-fees-collected) fee))
            
            (ok credit-amount))))

(define-public (update-impact-metrics (project-id uint) 
                                     (co2 uint) (trees uint) (hectares uint) 
                                     (communities uint) (biodiversity uint) (water uint))
    (let ((project (unwrap! (map-get? carbon-projects project-id) err-project-not-found)))
        
        ;; Only project owner can update
        (asserts! (is-eq tx-sender (get owner project)) err-unauthorized)
        
        (map-set impact-metrics project-id {
            co2-sequestered: co2,
            trees-planted: trees,
            hectares-protected: hectares,
            communities-benefited: communities,
            biodiversity-score: biodiversity,
            water-saved: water,
            last-updated: burn-block-height
        })
        
        (ok true)))

;; Admin Functions
(define-public (add-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (map-set verified-validators validator {
            is-active: true,
            total-validated: u0,
            reputation-score: u1000,
            registered-at: burn-block-height
        })
        (var-set active-validators (+ (var-get active-validators) u1))
        (ok true)))

(define-public (pause-platform)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set platform-paused true)
        (ok true)))

(define-public (unpause-platform)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set platform-paused false)
        (ok true)))

(define-public (withdraw-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= amount (var-get platform-fees-collected)) err-insufficient-credits)
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (var-set platform-fees-collected (- (var-get platform-fees-collected) amount))
        (ok amount)))