(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-VOTING-CLOSED u101)
(define-constant ERR_INVALID_DISPUTE u102)
(define-constant ERR_ALREADY_VOTED u103)
(define-constant ERR_NOT_ARBITRATOR u104)
(define-constant ERR_VOTING_NOT_STARTED u105)
(define-constant ERR_INVALID_VOTE u106)
(define-constant ERR_DISPUTE_RESOLVED u107)
(define-constant ERR_INSUFFICIENT_ARBITRATORS u108)
(define-constant ERR_INVALID_STAKE u109)
(define-constant ERR_SLASH_FAILED u110)
(define-constant ERR_REWARD_FAILED u111)
(define-constant ERR_INVALID_TIMESTAMP u112)
(define-constant ERR_DISPUTE_NOT_FOUND u113)
(define-constant ERR_INVALID_MAJORITY u114)
(define-constant ERR_INVALID_OUTCOME u115)
(define-constant ERR_UPDATE_FAILED u116)
(define-constant ERR_RANDOM_FAILED u117)
(define-constant ERR_ESCROW_NOT_FOUND u118)
(define-constant ERR_INVALID_GRACE_PERIOD u119)
(define-constant ERR_INVALID_VOTING_PERIOD u120)
(define-constant ERR_INVALID_MIN_VOTES u121)
(define-constant ERR_INVALID_MAX_ARBITRATORS u122)
(define-constant ERR_ARBITRATOR_ALREADY_REGISTERED u123)
(define-constant ERR_ARBITRATOR_NOT_FOUND u124)
(define-constant ERR_INVALID_REPUTATION u125)
(define-constant ERR_REPUTATION_UPDATE_FAILED u126)
(define-constant ERR_FEE_TRANSFER_FAILED u127)
(define-constant ERR_INVALID_FEE u128)
(define-constant ERR_DISPUTE_ALREADY_ACTIVE u129)
(define-constant ERR_INVALID_EVIDENCE_HASH u130)

(define-constant VOTE_DRIVER u1)
(define-constant VOTE_PASSENGER u2)
(define-constant VOTE_TIE u3)
(define-constant MIN_ARBITRATORS u3)
(define-constant MAX_ARBITRATORS u7)
(define-constant VOTING_PERIOD u2880)
(define-constant GRACE_PERIOD u1440)
(define-constant MIN_VOTES u3)
(define-constant SLASH_PERCENT u20)
(define-constant REWARD_PERCENT u10)
(define-constant MIN_STAKE u1000)
(define-constant REPUTATION_THRESHOLD u50)

(define-data-var next-dispute-id uint u0)
(define-data-var admin principal tx-sender)
(define-data-var escrow-contract principal 'SP000000000000000000002Q6VF78)
(define-data-var arbitrator-registry-contract principal 'SP000000000000000000002Q6VF78)
(define-data-var user-registry-contract principal 'SP000000000000000000002Q6VF78)
(define-data-var resolution-fee uint u500)

(define-map disputes
  uint
  {
    initiator: principal,
    driver: principal,
    passenger: principal,
    evidence-hash: (buff 32),
    start-block: uint,
    end-block: uint,
    arbitrators: (list 7 principal),
    votes-driver: uint,
    votes-passenger: uint,
    votes-tie: uint,
    outcome: uint,
    resolved: bool,
    total-stake: uint,
    min-votes: uint
  }
)

(define-map votes
  { dispute-id: uint, arbitrator: principal }
  uint
)

(define-map arbitrator-stakes
  principal
  uint
)

(define-map arbitrator-reputations
  principal
  uint
)

(define-read-only (get-dispute (id uint))
  (map-get? disputes id)
)

(define-read-only (get-vote (id uint) (arbitrator principal))
  (map-get? votes { dispute-id: id, arbitrator: arbitrator })
)

(define-read-only (get-arbitrator-stake (arbitrator principal))
  (default-to u0 (map-get? arbitrator-stakes arbitrator))
)

(define-read-only (get-arbitrator-reputation (arbitrator principal))
  (default-to u0 (map-get? arbitrator-reputations arbitrator))
)

(define-read-only (has-voted (id uint) (arbitrator principal))
  (is-some (get-vote id arbitrator))
)

(define-private (is-arbitrator (id uint) (arbitrator principal))
  (let ((dispute (unwrap! (get-dispute id) false)))
    (is-some (index-of (get arbitrators dispute) arbitrator))
  )
)

(define-private (validate-vote (vote uint))
  (if (or (is-eq vote VOTE_DRIVER) (is-eq vote VOTE_PASSENGER) (is-eq vote VOTE_TIE))
    (ok true)
    (err ERR_INVALID_VOTE)
  )
)

(define-private (validate-stake (stake uint))
  (if (>= stake MIN_STAKE)
    (ok true)
    (err ERR_INVALID_STAKE)
  )
)

(define-private (validate-reputation (rep uint))
  (if (>= rep REPUTATION_THRESHOLD)
    (ok true)
    (err ERR_INVALID_REPUTATION)
  )
)

(define-private (validate-dispute-id (id uint))
  (if (is-some (get-dispute id))
    (ok true)
    (err ERR_DISPUTE_NOT_FOUND)
  )
)

(define-private (validate-voting-period (id uint))
  (let ((dispute (unwrap! (get-dispute id) (err ERR_DISPUTE_NOT_FOUND))))
    (if (and (>= block-height (get start-block dispute)) (<= block-height (get end-block dispute)))
      (ok true)
      (err ERR_VOTING_CLOSED)
    )
  )
)

(define-private (calculate-majority (dispute { votes-driver: uint, votes-passenger: uint, votes-tie: uint }))
  (let (
    (vd (get votes-driver dispute))
    (vp (get votes-passenger dispute))
    (vt (get votes-tie dispute))
    (total (+ vd vp vt))
  )
    (if (>= total MIN_VOTES)
      (if (and (> vd vp) (> vd vt))
        VOTE_DRIVER
        (if (and (> vp vd) (> vp vt))
          VOTE_PASSENGER
          VOTE_TIE
        )
      )
      u0
    )
  )
)

(define-private (slash-stake (arbitrator principal) (amount uint))
  (let ((current-stake (get-arbitrator-stake arbitrator)))
    (if (>= current-stake amount)
      (begin
        (map-set arbitrator-stakes arbitrator (- current-stake amount))
        (ok amount)
      )
      (err ERR_SLASH_FAILED)
    )
  )
)

(define-private (reward-arbitrator (arbitrator principal) (amount uint))
  (let ((current-stake (get-arbitrator-stake arbitrator)))
    (map-set arbitrator-stakes arbitrator (+ current-stake amount))
    (ok true)
  )
)

(define-private (update-reputation (arbitrator principal) (delta int))
  (let ((current-rep (get-arbitrator-reputation arbitrator)))
    (map-set arbitrator-reputations arbitrator (as-max-len? (to-uint (+ (to-int current-rep) delta)) u1000000))
    (ok true)
  )
)

(define-public (register-arbitrator (stake uint))
  (begin
    (try! (validate-stake stake))
    (asserts! (is-none (map-get? arbitrator-stakes tx-sender)) (err ERR_ARBITRATOR_ALREADY_REGISTERED))
    (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))
    (map-set arbitrator-stakes tx-sender stake)
    (map-set arbitrator-reputations tx-sender u50)
    (ok true)
  )
)

(define-public (initiate-dispute 
  (driver principal) 
  (passenger principal) 
  (evidence-hash (buff 32)) 
  (arbitrators (list 7 principal))
  (total-stake uint)
)
  (let ((id (var-get next-dispute-id)))
    (asserts! (>= (len arbitrators) MIN_ARBITRATORS) (err ERR_INSUFFICIENT_ARBITRATORS))
    (asserts! (<= (len arbitrators) MAX_ARBITRATORS) (err ERR_INVALID_MAX_ARBITRATORS))
    (map-set disputes id
      {
        initiator: tx-sender,
        driver: driver,
        passenger: passenger,
        evidence-hash: evidence-hash,
        start-block: block-height,
        end-block: (+ block-height VOTING_PERIOD),
        arbitrators: arbitrators,
        votes-driver: u0,
        votes-passenger: u0,
        votes-tie: u0,
        outcome: u0,
        resolved: false,
        total-stake: total-stake,
        min-votes: MIN_VOTES
      }
    )
    (var-set next-dispute-id (+ id u1))
    (print { event: "dispute-initiated", id: id })
    (ok id)
  )
)

(define-public (vote-on-dispute (id uint) (vote uint))
  (let ((dispute (unwrap! (get-dispute id) (err ERR_DISPUTE_NOT_FOUND))))
    (asserts! (not (get resolved dispute)) (err ERR_DISPUTE_RESOLVED))
    (try! (validate-voting-period id))
    (try! (validate-vote vote))
    (asserts! (is-arbitrator id tx-sender) (err ERR_NOT_ARBITRATOR))
    (asserts! (not (has-voted id tx-sender)) (err ERR_ALREADY_VOTED))
    (try! (validate-reputation (get-arbitrator-reputation tx-sender)))
    (map-set votes { dispute-id: id, arbitrator: tx-sender } vote)
    (match vote
      VOTE_DRIVER (map-set disputes id (merge dispute { votes-driver: (+ (get votes-driver dispute) u1) }))
      VOTE_PASSENGER (map-set disputes id (merge dispute { votes-passenger: (+ (get votes-passenger dispute) u1) }))
      VOTE_TIE (map-set disputes id (merge dispute { votes-tie: (+ (get votes-tie dispute) u1) }))
    )
    (print { event: "vote-cast", id: id, voter: tx-sender, vote: vote })
    (ok true)
  )
)

(define-public (resolve-dispute (id uint))
  (let ((dispute (unwrap! (get-dispute id) (err ERR_DISPUTE_NOT_FOUND))))
    (asserts! (> block-height (get end-block dispute)) (err ERR_VOTING_NOT_STARTED))
    (asserts! (not (get resolved dispute)) (err ERR_DISPUTE_RESOLVED))
    (let ((outcome (calculate-majority (unwrap! dispute (err ERR_INVALID_MAJORITY)))))
      (asserts! (> outcome u0) (err ERR_INVALID_OUTCOME))
      (map-set disputes id (merge dispute { outcome: outcome, resolved: true }))
      (fold process-arbitrator-votes (get arbitrators dispute) { id: id, outcome: outcome, slash-pool: u0 })
      (try! (as-contract (stx-transfer? (get resolution-fee id) tx-sender (var-get admin))))
      (print { event: "dispute-resolved", id: id, outcome: outcome })
      (ok outcome)
    )
  )
)

(define-private (process-arbitrator-votes (arbitrator principal) (ctx { id: uint, outcome: uint, slash-pool: uint }))
  (let (
    (vote (default-to u0 (get-vote (get id ctx) arbitrator)))
    (stake (get-arbitrator-stake arbitrator))
    (slash-amount (/ (* stake SLASH_PERCENT) u100))
  )
    (if (is-eq vote (get outcome ctx))
      (begin
        (try! (update-reputation arbitrator 10))
        (try! (reward-arbitrator arbitrator (/ (get slash-pool ctx) (len (get arbitrators (get-dispute (get id ctx)))))))
      )
      (begin
        (try! (update-reputation arbitrator -10))
        (try! (slash-stake arbitrator slash-amount))
        (merge ctx { slash-pool: (+ (get slash-pool ctx) slash-amount) })
      )
    )
    ctx
  )
)

(define-public (set-escrow-contract (new-escrow principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_NOT_AUTHORIZED))
    (var-set escrow-contract new-escrow)
    (ok true)
  )
)

(define-public (set-resolution-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_NOT_AUTHORIZED))
    (asserts! (> new-fee u0) (err ERR_INVALID_FEE))
    (var-set resolution-fee new-fee)
    (ok true)
  )
)

(define-public (withdraw-stake (amount uint))
  (let ((current-stake (get-arbitrator-stake tx-sender)))
    (asserts! (>= current-stake amount) (err ERR_INVALID_STAKE))
    (map-set arbitrator-stakes tx-sender (- current-stake amount))
    (as-contract (stx-transfer? amount tx-sender tx-sender))
    (ok true)
  )
)