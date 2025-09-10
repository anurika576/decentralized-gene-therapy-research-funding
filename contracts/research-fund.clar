;; Research Fund Smart Contract
;; Gene therapy research funding platform with milestone-based releases
;; Features: proposal submission, funding allocation, milestone tracking, transparent distribution

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u404))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_INVALID_AMOUNT (err u403))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_STATUS (err u410))
(define-constant ERR_MILESTONE_NOT_FOUND (err u411))
(define-constant ERR_ALREADY_COMPLETED (err u412))
(define-constant ERR_INVALID_MILESTONE (err u413))
(define-constant MIN_FUNDING_AMOUNT u1000000) ;; 1 STX minimum
(define-constant PLATFORM_FEE_PERCENT u2) ;; 2% platform fee
(define-constant MAX_MILESTONES u10)

;; Proposal Status
(define-constant STATUS_SUBMITTED u1)
(define-constant STATUS_UNDER_REVIEW u2)
(define-constant STATUS_APPROVED u3)
(define-constant STATUS_FUNDED u4)
(define-constant STATUS_ACTIVE u5)
(define-constant STATUS_COMPLETED u6)
(define-constant STATUS_REJECTED u7)

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var total-funds-raised uint u0)
(define-data-var total-funds-distributed uint u0)
(define-data-var platform-fees-collected uint u0)

;; Data Maps
;; Research Proposals
(define-map research-proposals
  uint ;; proposal-id
  {
    researcher: principal,
    title: (string-utf8 200),
    description: (string-utf8 1000),
    funding-goal: uint,
    current-funding: uint,
    duration-months: uint,
    therapy-type: (string-utf8 100),
    institution: (string-utf8 200),
    status: uint,
    submission-height: uint,
    approval-height: uint,
    completion-height: uint,
    total-milestones: uint,
    completed-milestones: uint
  }
)

;; Research Milestones
(define-map proposal-milestones
  {proposal-id: uint, milestone-id: uint}
  {
    title: (string-utf8 200),
    description: (string-utf8 500),
    funding-percentage: uint,
    target-completion: uint,
    actual-completion: uint,
    is-completed: bool,
    verification-required: bool,
    evidence: (optional (string-utf8 500))
  }
)

;; Funding Contributions
(define-map funding-contributions
  {proposal-id: uint, funder: principal}
  {
    amount: uint,
    contribution-height: uint,
    is-refunded: bool
  }
)

;; Total contributions per funder
(define-map funder-totals
  principal
  {
    total-contributed: uint,
    proposals-funded: uint,
    successful-investments: uint
  }
)

;; Proposal funding history
(define-map proposal-funders
  uint ;; proposal-id
  (list 50 principal)
)

;; Review committee (simplified governance)
(define-map review-committee
  principal
  {
    expertise-area: (string-utf8 100),
    reputation-score: uint,
    reviews-completed: uint,
    is-active: bool
  }
)

;; Proposal reviews
(define-map proposal-reviews
  {proposal-id: uint, reviewer: principal}
  {
    scientific-score: uint,
    feasibility-score: uint,
    impact-score: uint,
    overall-recommendation: bool,
    comments: (string-utf8 500),
    review-height: uint
  }
)

;; Platform statistics
(define-map daily-stats
  uint ;; block-height-day
  {
    proposals-submitted: uint,
    funding-raised: uint,
    milestones-completed: uint
  }
)

;; Public Functions

;; Submit research proposal
(define-public (submit-proposal
    (title (string-utf8 200))
    (description (string-utf8 1000))
    (funding-goal uint)
    (duration-months uint)
    (therapy-type (string-utf8 100))
    (institution (string-utf8 200))
    (milestone-count uint)
  )
  (let 
    (
      (proposal-id (+ (var-get proposal-counter) u1))
    )
    
    ;; Validation
    (asserts! (>= funding-goal MIN_FUNDING_AMOUNT) ERR_INVALID_AMOUNT)
    (asserts! (and (> milestone-count u0) (<= milestone-count MAX_MILESTONES)) ERR_INVALID_MILESTONE)
    (asserts! (> duration-months u0) ERR_INVALID_AMOUNT)
    
    ;; Create proposal
    (map-set research-proposals proposal-id
      {
        researcher: tx-sender,
        title: title,
        description: description,
        funding-goal: funding-goal,
        current-funding: u0,
        duration-months: duration-months,
        therapy-type: therapy-type,
        institution: institution,
        status: STATUS_SUBMITTED,
        submission-height: block-height,
        approval-height: u0,
        completion-height: u0,
        total-milestones: milestone-count,
        completed-milestones: u0
      }
    )
    
    ;; Initialize empty funder list
    (map-set proposal-funders proposal-id (list))
    
    ;; Update counter
    (var-set proposal-counter proposal-id)
    
    (ok proposal-id)
  )
)

;; Add milestone to proposal
(define-public (add-milestone
    (proposal-id uint)
    (milestone-id uint)
    (title (string-utf8 200))
    (description (string-utf8 500))
    (funding-percentage uint)
    (target-completion uint)
  )
  (let 
    (
      (proposal-data (unwrap! (map-get? research-proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    )
    
    ;; Validation
    (asserts! (is-eq (get researcher proposal-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (<= milestone-id (get total-milestones proposal-data)) ERR_INVALID_MILESTONE)
    (asserts! (and (> funding-percentage u0) (<= funding-percentage u100)) ERR_INVALID_AMOUNT)
    
    ;; Add milestone
    (map-set proposal-milestones {proposal-id: proposal-id, milestone-id: milestone-id}
      {
        title: title,
        description: description,
        funding-percentage: funding-percentage,
        target-completion: target-completion,
        actual-completion: u0,
        is-completed: false,
        verification-required: true,
        evidence: none
      }
    )
    
    (ok true)
  )
)

;; Fund research proposal
(define-public (fund-proposal (proposal-id uint) (amount uint))
  (let 
    (
      (proposal-data (unwrap! (map-get? research-proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
      (current-contribution (default-to {amount: u0, contribution-height: u0, is-refunded: false}
                              (map-get? funding-contributions {proposal-id: proposal-id, funder: tx-sender})))
      (funder-data (default-to {total-contributed: u0, proposals-funded: u0, successful-investments: u0}
                    (map-get? funder-totals tx-sender)))
      (current-funders (default-to (list) (map-get? proposal-funders proposal-id)))
      (platform-fee (/ (* amount PLATFORM_FEE_PERCENT) u100))
      (net-amount (- amount platform-fee))
    )
    
    ;; Validation
    (asserts! (>= amount MIN_FUNDING_AMOUNT) ERR_INVALID_AMOUNT)
    (asserts! (is-eq (get status proposal-data) STATUS_APPROVED) ERR_INVALID_STATUS)
    (asserts! (< (get current-funding proposal-data) (get funding-goal proposal-data)) ERR_INVALID_AMOUNT)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update proposal funding
    (map-set research-proposals proposal-id
      (merge proposal-data 
        {
          current-funding: (+ (get current-funding proposal-data) net-amount),
          status: (if (>= (+ (get current-funding proposal-data) net-amount) (get funding-goal proposal-data))
                      STATUS_FUNDED
                      STATUS_APPROVED)
        }
      )
    )
    
    ;; Update or create funding contribution
    (map-set funding-contributions {proposal-id: proposal-id, funder: tx-sender}
      {
        amount: (+ (get amount current-contribution) net-amount),
        contribution-height: block-height,
        is-refunded: false
      }
    )
    
    ;; Update funder totals
    (map-set funder-totals tx-sender
      {
        total-contributed: (+ (get total-contributed funder-data) net-amount),
        proposals-funded: (if (is-eq (get amount current-contribution) u0)
                            (+ (get proposals-funded funder-data) u1)
                            (get proposals-funded funder-data)),
        successful-investments: (get successful-investments funder-data)
      }
    )
    
    ;; Add to funders list if first contribution
    (if (is-eq (get amount current-contribution) u0)
      (map-set proposal-funders proposal-id
        (unwrap! (as-max-len? (append current-funders tx-sender) u50) ERR_INVALID_AMOUNT))
      true
    )
    
    ;; Update global stats
    (var-set total-funds-raised (+ (var-get total-funds-raised) net-amount))
    (var-set platform-fees-collected (+ (var-get platform-fees-collected) platform-fee))
    
    (ok net-amount)
  )
)

;; Complete milestone and release funding
(define-public (complete-milestone
    (proposal-id uint)
    (milestone-id uint)
    (evidence (string-utf8 500))
  )
  (let 
    (
      (proposal-data (unwrap! (map-get? research-proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
      (milestone-data (unwrap! (map-get? proposal-milestones {proposal-id: proposal-id, milestone-id: milestone-id})
                              ERR_MILESTONE_NOT_FOUND))
      (funding-amount (/ (* (get current-funding proposal-data) (get funding-percentage milestone-data)) u100))
    )
    
    ;; Validation
    (asserts! (is-eq (get researcher proposal-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get is-completed milestone-data)) ERR_ALREADY_COMPLETED)
    (asserts! (is-eq (get status proposal-data) STATUS_FUNDED) ERR_INVALID_STATUS)
    
    ;; Mark milestone as completed
    (map-set proposal-milestones {proposal-id: proposal-id, milestone-id: milestone-id}
      (merge milestone-data
        {
          actual-completion: block-height,
          is-completed: true,
          evidence: (some evidence)
        }
      )
    )
    
    ;; Release milestone funding
    (try! (as-contract (stx-transfer? funding-amount tx-sender (get researcher proposal-data))))
    
    ;; Update proposal
    (let 
      (
        (new-completed-milestones (+ (get completed-milestones proposal-data) u1))
      )
      (map-set research-proposals proposal-id
        (merge proposal-data
          {
            completed-milestones: new-completed-milestones,
            status: (if (is-eq new-completed-milestones (get total-milestones proposal-data))
                        STATUS_COMPLETED
                        STATUS_ACTIVE),
            completion-height: (if (is-eq new-completed-milestones (get total-milestones proposal-data))
                                 block-height
                                 (get completion-height proposal-data))
          }
        )
      )
    )
    
    ;; Update distributed funds
    (var-set total-funds-distributed (+ (var-get total-funds-distributed) funding-amount))
    
    (ok funding-amount)
  )
)

;; Approve proposal (governance function)
(define-public (approve-proposal (proposal-id uint))
  (let 
    (
      (proposal-data (unwrap! (map-get? research-proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    )
    
    ;; Only contract owner can approve for now (simplified governance)
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status proposal-data) STATUS_SUBMITTED) ERR_INVALID_STATUS)
    
    ;; Update proposal status
    (map-set research-proposals proposal-id
      (merge proposal-data
        {
          status: STATUS_APPROVED,
          approval-height: block-height
        }
      )
    )
    
    (ok true)
  )
)

;; Join review committee
(define-public (join-review-committee (expertise-area (string-utf8 100)))
  (let 
    (
      (existing-reviewer (map-get? review-committee tx-sender))
    )
    
    ;; Check if already a reviewer
    (asserts! (is-none existing-reviewer) ERR_ALREADY_EXISTS)
    
    ;; Add to review committee
    (map-set review-committee tx-sender
      {
        expertise-area: expertise-area,
        reputation-score: u100, ;; Starting reputation
        reviews-completed: u0,
        is-active: true
      }
    )
    
    (ok true)
  )
)

;; Submit proposal review
(define-public (submit-review
    (proposal-id uint)
    (scientific-score uint)
    (feasibility-score uint)
    (impact-score uint)
    (overall-recommendation bool)
    (comments (string-utf8 500))
  )
  (let 
    (
      (proposal-data (unwrap! (map-get? research-proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
      (reviewer-data (unwrap! (map-get? review-committee tx-sender) ERR_UNAUTHORIZED))
    )
    
    ;; Validation
    (asserts! (get is-active reviewer-data) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status proposal-data) STATUS_UNDER_REVIEW) ERR_INVALID_STATUS)
    (asserts! (<= scientific-score u100) ERR_INVALID_AMOUNT)
    (asserts! (<= feasibility-score u100) ERR_INVALID_AMOUNT)
    (asserts! (<= impact-score u100) ERR_INVALID_AMOUNT)
    
    ;; Submit review
    (map-set proposal-reviews {proposal-id: proposal-id, reviewer: tx-sender}
      {
        scientific-score: scientific-score,
        feasibility-score: feasibility-score,
        impact-score: impact-score,
        overall-recommendation: overall-recommendation,
        comments: comments,
        review-height: block-height
      }
    )
    
    ;; Update reviewer stats
    (map-set review-committee tx-sender
      (merge reviewer-data
        {
          reviews-completed: (+ (get reviews-completed reviewer-data) u1)
        }
      )
    )
    
    (ok true)
  )
)

;; Read-only Functions

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? research-proposals proposal-id)
)

;; Get milestone details
(define-read-only (get-milestone (proposal-id uint) (milestone-id uint))
  (map-get? proposal-milestones {proposal-id: proposal-id, milestone-id: milestone-id})
)

;; Get funding contribution
(define-read-only (get-funding-contribution (proposal-id uint) (funder principal))
  (map-get? funding-contributions {proposal-id: proposal-id, funder: funder})
)

;; Get funder totals
(define-read-only (get-funder-totals (funder principal))
  (map-get? funder-totals funder)
)

;; Get proposal funders
(define-read-only (get-proposal-funders (proposal-id uint))
  (map-get? proposal-funders proposal-id)
)

;; Get proposal count
(define-read-only (get-proposal-count)
  (var-get proposal-counter)
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  {
    total-proposals: (var-get proposal-counter),
    total-funds-raised: (var-get total-funds-raised),
    total-funds-distributed: (var-get total-funds-distributed),
    platform-fees-collected: (var-get platform-fees-collected)
  }
)

;; Get reviewer profile
(define-read-only (get-reviewer-profile (reviewer principal))
  (map-get? review-committee reviewer)
)

;; Get proposal review
(define-read-only (get-proposal-review (proposal-id uint) (reviewer principal))
  (map-get? proposal-reviews {proposal-id: proposal-id, reviewer: reviewer})
)

;; Calculate funding progress
(define-read-only (get-funding-progress (proposal-id uint))
  (match (map-get? research-proposals proposal-id)
    proposal-data
    (ok {
      current-funding: (get current-funding proposal-data),
      funding-goal: (get funding-goal proposal-data),
      progress-percentage: (/ (* (get current-funding proposal-data) u100) (get funding-goal proposal-data)),
      is-fully-funded: (>= (get current-funding proposal-data) (get funding-goal proposal-data))
    })
    ERR_PROPOSAL_NOT_FOUND
  )
)

;; Get milestone progress
(define-read-only (get-milestone-progress (proposal-id uint))
  (match (map-get? research-proposals proposal-id)
    proposal-data
    (ok {
      completed-milestones: (get completed-milestones proposal-data),
      total-milestones: (get total-milestones proposal-data),
      completion-percentage: (/ (* (get completed-milestones proposal-data) u100) (get total-milestones proposal-data))
    })
    ERR_PROPOSAL_NOT_FOUND
  )
)
