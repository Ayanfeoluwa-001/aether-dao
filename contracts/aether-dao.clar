;; --------------------------------------------------
;; AETHER-DAO
;; A modular DAO operating system on Stacks
;; Features: Quadratic Voting, Multi-Treasury, NFT Membership,
;; Reputation Rewards, DAO Alliances, Grants/Bounties, DeFi Yield
;; --------------------------------------------------

;; ------------------------
;; DATA STRUCTURES
;; ------------------------

(define-data-var dao-treasuries {dev: uint, community: uint, insurance: uint} {dev: u0, community: u0, insurance: u0})
(define-map members principal { reputation: uint, stake: uint, badge: uint })
(define-map proposals uint { proposer: principal, description: (string-ascii 256), votes-for: uint, votes-against: uint, executed: bool })
(define-data-var next-proposal-id uint u0)

(define-map alliances principal { ally: principal, share: uint })
(define-map dao-reputation principal uint)

;; NFT for dynamic DAO membership
(define-non-fungible-token dao-badge uint)

;; Bounties
(define-map bounties uint { creator: principal, reward: uint, description: (string-ascii 256), completed: bool })
(define-data-var next-bounty-id uint u0)

;; ------------------------
;; UTILS
;; ------------------------

(define-private (sqrt (x uint)) ;; naive integer sqrt
  (if (< x u2) x
      (let ((z (/ (+ x u1) u2)))
        (if (< z x) z x))))

;; Quadratic voting power
(define-private (get-vote-power (user principal))
  (match (map-get? members user)
    member-data (sqrt (get stake member-data))
    u0))

;; ------------------------
;; MEMBERSHIP
;; ------------------------

(define-public (join-dao (stake-amount uint))
  (begin
    (asserts! (> stake-amount u0) (err u3)) ;; Ensure stake amount is positive
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    (map-set members tx-sender { reputation: u0, stake: stake-amount, badge: u1 })
    (ok true)))

;; Mint/upgrade dynamic NFT badge
(define-public (upgrade-badge (new-level uint))
  (let ((member-data (unwrap-panic (map-get? members tx-sender))))
    (asserts! (> new-level (get badge member-data)) (err u4)) ;; New level must be higher
    (try! (nft-mint? dao-badge new-level tx-sender))
    (map-set members tx-sender 
      { 
        reputation: (get reputation member-data), 
        stake: (get stake member-data), 
        badge: new-level 
      })
    (ok new-level)))

;; ------------------------
;; PROPOSALS & VOTING
;; ------------------------

(define-public (create-proposal (description (string-ascii 256)))
  (let ((id (var-get next-proposal-id)))
    (asserts! (> (len description) u0) (err u5)) ;; Ensure description is not empty
    (map-set proposals id { proposer: tx-sender, description: description, votes-for: u0, votes-against: u0, executed: false })
    (var-set next-proposal-id (+ id u1))
    (ok id)))

(define-public (vote (proposal-id uint) (support bool))
  (let ((power (get-vote-power tx-sender))
        (proposal (unwrap! (map-get? proposals proposal-id) (err u6)))) ;; Ensure proposal exists
    (asserts! (> power u0) (err u7)) ;; Ensure voter has voting power
    (asserts! (not (get executed proposal)) (err u8)) ;; Ensure proposal is not executed
    (if support
        (map-set proposals proposal-id (merge proposal { votes-for: (+ (get votes-for proposal) power) }))
        (map-set proposals proposal-id (merge proposal { votes-against: (+ (get votes-against proposal) power) })))
    (ok power)))

;; ------------------------
;; TREASURY
;; ------------------------

(define-public (deposit-treasury (vault (string-ascii 32)) (amount uint))
  (let ((current-treasuries (var-get dao-treasuries)))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (asserts! (or (is-eq vault "dev") 
                  (is-eq vault "community") 
                  (is-eq vault "insurance")) 
              (err u1)) ;; Invalid treasury type
    (if (is-eq vault "dev")
        (var-set dao-treasuries (merge current-treasuries { dev: (+ amount (get dev current-treasuries)) }))
        (if (is-eq vault "community")
            (var-set dao-treasuries (merge current-treasuries { community: (+ amount (get community current-treasuries)) }))
            (var-set dao-treasuries (merge current-treasuries { insurance: (+ amount (get insurance current-treasuries)) }))))
    (ok true)))

;; ------------------------
;; BOUNTIES
;; ------------------------

(define-public (create-bounty (reward uint) (description (string-ascii 256)))
  (let ((id (var-get next-bounty-id)))
    (asserts! (> reward u0) (err u9)) ;; Ensure reward is positive
    (asserts! (> (len description) u0) (err u10)) ;; Ensure description is not empty
    (map-set bounties id { creator: tx-sender, reward: reward, description: description, completed: false })
    (var-set next-bounty-id (+ id u1))
    (ok id)))

(define-public (complete-bounty (bounty-id uint) (worker principal))
  (let ((bounty (unwrap! (map-get? bounties bounty-id) (err u11))))
    (asserts! (not (get completed bounty)) (err u12))
    (try! (stx-transfer? (get reward bounty) (as-contract tx-sender) worker))
    (map-set bounties bounty-id 
      (merge bounty { completed: true }))
    (ok true)))

;; ------------------------
;; ALLIANCES
;; ------------------------

(define-public (form-alliance (other-dao principal) (share uint))
  (begin
    (asserts! (not (is-eq tx-sender other-dao)) (err u13)) ;; Cannot form alliance with self
    (asserts! (> share u0) (err u14)) ;; Share must be positive
    (map-set alliances tx-sender { ally: other-dao, share: share })
    (ok true)))

;; ------------------------
;; REPUTATION
;; ------------------------

;; Only contract owner can add reputation points
(define-constant contract-owner tx-sender)

(define-public (add-reputation (user principal) (points uint))
  (begin 
    (asserts! (is-eq tx-sender contract-owner) (err u15)) ;; Only contract owner can add points
    (asserts! (> points u0) (err u16)) ;; Points must be positive
    (let ((current-rep (default-to u0 (map-get? dao-reputation user))))
      (map-set dao-reputation user (+ current-rep points))
      (ok (+ current-rep points)))))
