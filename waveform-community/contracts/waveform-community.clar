;; WaveForm Community DAO Smart Contract
;; A simplified governance platform with dynamic voting mechanisms

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-voted (err u102))
(define-constant err-proposal-closed (err u103))
(define-constant err-insufficient-weight (err u104))
(define-constant err-invalid-input (err u105))

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var min-voting-weight uint u1)

;; Proposal Types
(define-constant RIPPLE u1)  ;; Routine decisions
(define-constant SURGE u2)   ;; Major proposals
(define-constant TSUNAMI u3) ;; Emergency decisions

;; Data Maps
(define-map proposals
  uint
  {
    proposer: principal,
    title: (string-ascii 100),
    proposal-type: uint,
    votes-for: uint,
    votes-against: uint,
    start-block: uint,
    end-block: uint,
    executed: bool,
    active: bool
  }
)

(define-map member-votes
  {proposal-id: uint, voter: principal}
  {vote: bool, weight: uint, block-height: uint}
)

(define-map member-reputation
  principal
  {
    contribution-score: uint,
    voting-weight: uint,
    proposals-created: uint,
    votes-cast: uint,
    last-active-block: uint
  }
)

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-member-reputation (member principal))
  (default-to
    {
      contribution-score: u0,
      voting-weight: u1,
      proposals-created: u0,
      votes-cast: u0,
      last-active-block: u0
    }
    (map-get? member-reputation member)
  )
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? member-votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-proposal-count)
  (var-get proposal-counter)
)

(define-read-only (calculate-voting-weight (member principal))
  (let
    (
      (rep (get-member-reputation member))
      (base-weight (get voting-weight rep))
      (contribution (get contribution-score rep))
    )
    ;; Weight increases with contribution score
    (+ base-weight (/ contribution u100))
  )
)

;; Public functions
(define-public (create-proposal (title (string-ascii 100)) (proposal-type uint) (duration uint))
  (let
    (
      (proposal-id (+ (var-get proposal-counter) u1))
      (current-block block-height)
      (rep (get-member-reputation tx-sender))
    )
    ;; Validate proposal type
    (asserts! (or (is-eq proposal-type RIPPLE)
                  (or (is-eq proposal-type SURGE)
                      (is-eq proposal-type TSUNAMI)))
              err-invalid-input)
    
    ;; Validate duration
    (asserts! (and (> duration u0) (< duration u10000)) err-invalid-input)
    
    ;; Create proposal
    (map-set proposals proposal-id
      {
        proposer: tx-sender,
        title: title,
        proposal-type: proposal-type,
        votes-for: u0,
        votes-against: u0,
        start-block: current-block,
        end-block: (+ current-block duration),
        executed: false,
        active: true
      }
    )
    
    ;; Update proposer reputation
    (map-set member-reputation tx-sender
      (merge rep {
        proposals-created: (+ (get proposals-created rep) u1),
        last-active-block: current-block
      })
    )
    
    ;; Increment counter
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

(define-public (cast-vote (proposal-id uint) (vote-for bool))
  (let
    (
      (proposal (unwrap! (get-proposal proposal-id) err-not-found))
      (voter-weight (calculate-voting-weight tx-sender))
      (rep (get-member-reputation tx-sender))
      (current-block block-height)
    )
    ;; Check if proposal is active
    (asserts! (get active proposal) err-proposal-closed)
    (asserts! (< current-block (get end-block proposal)) err-proposal-closed)
    
    ;; Check if already voted
    (asserts! (is-none (get-vote proposal-id tx-sender)) err-already-voted)
    
    ;; Check minimum weight
    (asserts! (>= voter-weight (var-get min-voting-weight)) err-insufficient-weight)
    
    ;; Record vote
    (map-set member-votes
      {proposal-id: proposal-id, voter: tx-sender}
      {vote: vote-for, weight: voter-weight, block-height: current-block}
    )
    
    ;; Update proposal vote counts
    (map-set proposals proposal-id
      (merge proposal {
        votes-for: (if vote-for
                      (+ (get votes-for proposal) voter-weight)
                      (get votes-for proposal)),
        votes-against: (if vote-for
                          (get votes-against proposal)
                          (+ (get votes-against proposal) voter-weight))
      })
    )
    
    ;; Update voter reputation
    (map-set member-reputation tx-sender
      (merge rep {
        votes-cast: (+ (get votes-cast rep) u1),
        last-active-block: current-block
      })
    )
    
    (ok true)
  )
)

(define-public (close-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (get-proposal proposal-id) err-not-found))
      (current-block block-height)
    )
    ;; Check if voting period ended
    (asserts! (>= current-block (get end-block proposal)) err-proposal-closed)
    (asserts! (get active proposal) err-proposal-closed)
    
    ;; Close proposal
    (map-set proposals proposal-id
      (merge proposal {active: false})
    )
    
    (ok true)
  )
)

(define-public (add-contribution-score (member principal) (score uint))
  (let
    (
      (rep (get-member-reputation member))
    )
    ;; Only contract owner can add contribution scores
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    ;; Update contribution score
    (map-set member-reputation member
      (merge rep {
        contribution-score: (+ (get contribution-score rep) score),
        voting-weight: (+ (get voting-weight rep) (/ score u100))
      })
    )
    
    (ok true)
  )
)

(define-public (set-min-voting-weight (weight uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set min-voting-weight weight)
    (ok true)
  )
)

;; Initialize contract
(begin
  (map-set member-reputation contract-owner
    {
      contribution-score: u1000,
      voting-weight: u10,
      proposals-created: u0,
      votes-cast: u0,
      last-active-block: block-height
    }
  )
)