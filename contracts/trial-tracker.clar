;; Trial Tracker Smart Contract
;; Clinical trial lifecycle tracking for gene therapy research
;; Features: trial registration, phase management, participant tracking, outcomes, adverse events

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_TRIAL_NOT_FOUND (err u404))
(define-constant ERR_INVALID_INPUT (err u405))
(define-constant ERR_PHASE_OUT_OF_ORDER (err u406))
(define-constant ERR_PHASE_NOT_FOUND (err u407))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_STATUS (err u410))
(define-constant ERR_PARTICIPANT_NOT_FOUND (err u411))
(define-constant ERR_EVENT_NOT_FOUND (err u412))

;; Trial Phases (1..4 typical)
(define-constant PHASE_I u1)
(define-constant PHASE_II u2)
(define-constant PHASE_III u3)
(define-constant PHASE_IV u4)

;; Trial Status
(define-constant STATUS_REGISTERED u1)
(define-constant STATUS_ACTIVE u2)
(define-constant STATUS_SUSPENDED u3)
(define-constant STATUS_COMPLETED u4)
(define-constant STATUS_TERMINATED u5)

;; Data Variables
(define-data-var trial-counter uint u0)
(define-data-var adverse-event-counter uint u0)
(define-data-var participant-counter uint u0)

;; Data Maps
;; Trial Registry
(define-map trials
  uint ;; trial-id
  {
    sponsor: principal,
    title: (string-utf8 150),
    condition: (string-utf8 100),
    therapy: (string-utf8 100),
    registration-height: uint,
    status: uint,
    current-phase: uint,
    target-enrollment: uint,
    enrolled-count: uint,
    site-country: (string-utf8 50),
    irb-approval: bool,
    public-summary: (string-utf8 500)
  }
)

;; Trial Phase Details
(define-map trial-phases
  {trial-id: uint, phase: uint}
  {
    start-height: uint,
    end-height: uint,
    target-duration-blocks: uint,
    objectives: (string-utf8 300),
    is-completed: bool
  }
)

;; Participants
(define-map participants
  {trial-id: uint, participant-id: uint}
  {
    subject-code: (string-ascii 32),
    enrollment-height: uint,
    is-active: bool,
    age: uint,
    sex: (string-ascii 1),
    notes: (optional (string-utf8 200))
  }
)

;; Participant index per trial
(define-map trial-participant-index
  uint ;; trial-id
  (list 1000 uint)
)

;; Outcomes per trial
(define-map trial-outcomes
  uint ;; trial-id
  {
    primary-outcome: (optional (string-utf8 300)),
    secondary-outcomes: (list 10 (string-utf8 200)),
    outcome-height: uint,
    success-indicator: (optional bool)
  }
)

;; Adverse Events
(define-map adverse-events
  uint ;; event-id
  {
    trial-id: uint,
    participant-id: uint,
    severity: (string-ascii 10),
    description: (string-utf8 300),
    event-height: uint,
    resolved: bool,
    resolution-notes: (optional (string-utf8 200))
  }
)

;; Trial Monitors (authorized controllers for updates)
(define-map trial-monitors
  {trial-id: uint, monitor: principal}
  {
    role: (string-utf8 50),
    added-height: uint,
    is-active: bool
  }
)

;; Public Functions

;; Register a new clinical trial
(define-public (register-trial
    (title (string-utf8 150))
    (condition (string-utf8 100))
    (therapy (string-utf8 100))
    (target-enrollment uint)
    (site-country (string-utf8 50))
    (public-summary (string-utf8 500))
    (irb-approval bool)
  )
  (let
    (
      (trial-id (+ (var-get trial-counter) u1))
    )
    (asserts! (> target-enrollment u0) ERR_INVALID_INPUT)
    (asserts! irb-approval ERR_INVALID_INPUT)

    (map-set trials trial-id
      {
        sponsor: tx-sender,
        title: title,
        condition: condition,
        therapy: therapy,
        registration-height: block-height,
        status: STATUS_REGISTERED,
        current-phase: PHASE_I,
        target-enrollment: target-enrollment,
        enrolled-count: u0,
        site-country: site-country,
        irb-approval: irb-approval,
        public-summary: public-summary
      }
    )

    ;; Initialize participant index list
    (map-set trial-participant-index trial-id (list))

    ;; Initialize phase I placeholder
    (map-set trial-phases {trial-id: trial-id, phase: PHASE_I}
      {
        start-height: u0,
        end-height: u0,
        target-duration-blocks: u0,
        objectives: u"",
        is-completed: false
      }
    )

    (var-set trial-counter trial-id)
    (ok trial-id)
  )
)

;; Add or update a phase configuration
(define-public (configure-phase
    (trial-id uint)
    (phase uint)
    (target-duration-blocks uint)
    (objectives (string-utf8 300))
  )
  (let
    (
      (trial (unwrap! (map-get? trials trial-id) ERR_TRIAL_NOT_FOUND))
    )
    (asserts! (or (is-eq tx-sender (get sponsor trial))
                  (is-monitor-authorized trial-id tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (and (>= phase PHASE_I) (<= phase PHASE_IV)) ERR_INVALID_INPUT)
    (asserts! (> target-duration-blocks u0) ERR_INVALID_INPUT)

    (map-set trial-phases {trial-id: trial-id, phase: phase}
      {
        start-height: u0,
        end-height: u0,
        target-duration-blocks: target-duration-blocks,
        objectives: objectives,
        is-completed: false
      }
    )
    (ok true)
  )
)

;; Start a phase
(define-public (start-phase (trial-id uint) (phase uint))
  (let
    (
      (trial (unwrap! (map-get? trials trial-id) ERR_TRIAL_NOT_FOUND))
      (phase-data (unwrap! (map-get? trial-phases {trial-id: trial-id, phase: phase}) ERR_PHASE_NOT_FOUND))
    )
    (asserts! (or (is-eq tx-sender (get sponsor trial)) (is-monitor-authorized trial-id tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (is-eq phase (get current-phase trial)) ERR_PHASE_OUT_OF_ORDER)
    (asserts! (is-eq (get start-height phase-data) u0) ERR_INVALID_STATUS)

    ;; Activate trial if not active
    (map-set trials trial-id
      (merge trial {status: (if (is-eq (get status trial) STATUS_REGISTERED) STATUS_ACTIVE (get status trial))})
    )

    ;; Set phase start
    (map-set trial-phases {trial-id: trial-id, phase: phase}
      (merge phase-data {start-height: block-height})
    )
    (ok true)
  )
)

;; Complete a phase
(define-public (complete-phase (trial-id uint) (phase uint))
  (let
    (
      (trial (unwrap! (map-get? trials trial-id) ERR_TRIAL_NOT_FOUND))
      (phase-data (unwrap! (map-get? trial-phases {trial-id: trial-id, phase: phase}) ERR_PHASE_NOT_FOUND))
    )
    (asserts! (or (is-eq tx-sender (get sponsor trial)) (is-monitor-authorized trial-id tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (is-eq phase (get current-phase trial)) ERR_PHASE_OUT_OF_ORDER)
    (asserts! (is-eq (get end-height phase-data) u0) ERR_INVALID_STATUS)

    ;; Complete phase
    (map-set trial-phases {trial-id: trial-id, phase: phase}
      (merge phase-data {end-height: block-height, is-completed: true})
    )

    ;; Advance trial phase or complete
    (let ((next-phase (+ phase u1)))
      (map-set trials trial-id
        (merge trial
          {
            current-phase: (if (<= next-phase PHASE_IV) next-phase phase),
            status: (if (> next-phase PHASE_IV) STATUS_COMPLETED (get status trial))
          }
        )
      )
    )
    (ok true)
  )
)

;; Suspend or resume a trial
(define-public (set-trial-status (trial-id uint) (status uint))
  (let ((trial (unwrap! (map-get? trials trial-id) ERR_TRIAL_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender (get sponsor trial)) (is-monitor-authorized trial-id tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq status STATUS_SUSPENDED)
                  (is-eq status STATUS_ACTIVE)
                  (is-eq status STATUS_TERMINATED)) ERR_INVALID_STATUS)
    (map-set trials trial-id (merge trial {status: status}))
    (ok true)
  )
)

;; Enroll a participant
(define-public (enroll-participant
    (trial-id uint)
    (subject-code (string-ascii 32))
    (age uint)
    (sex (string-ascii 1))
    (notes (optional (string-utf8 200)))
  )
  (let
    (
      (trial (unwrap! (map-get? trials trial-id) ERR_TRIAL_NOT_FOUND))
      (new-participant-id (+ (var-get participant-counter) u1))
      (p-index (default-to (list) (map-get? trial-participant-index trial-id)))
    )
    (asserts! (or (is-eq tx-sender (get sponsor trial)) (is-monitor-authorized trial-id tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status trial) STATUS_ACTIVE) ERR_INVALID_STATUS)
    (asserts! (> age u0) ERR_INVALID_INPUT)
    (asserts! (<= (get enrolled-count trial) (get target-enrollment trial)) ERR_INVALID_INPUT)

    (map-set participants {trial-id: trial-id, participant-id: new-participant-id}
      {
        subject-code: subject-code,
        enrollment-height: block-height,
        is-active: true,
        age: age,
        sex: sex,
        notes: notes
      }
    )

    (map-set trial-participant-index trial-id
      (unwrap! (as-max-len? (append p-index new-participant-id) u1000) ERR_INVALID_INPUT)
    )

    (map-set trials trial-id
      (merge trial {enrolled-count: (+ (get enrolled-count trial) u1)})
    )

    (var-set participant-counter new-participant-id)
    (ok new-participant-id)
  )
)

;; Record an adverse event
(define-public (record-adverse-event
    (trial-id uint)
    (participant-id uint)
    (severity (string-ascii 10))
    (description (string-utf8 300))
  )
  (let
    (
      (trial (unwrap! (map-get? trials trial-id) ERR_TRIAL_NOT_FOUND))
      (participant (unwrap! (map-get? participants {trial-id: trial-id, participant-id: participant-id}) ERR_PARTICIPANT_NOT_FOUND))
      (event-id (+ (var-get adverse-event-counter) u1))
    )
    (asserts! (or (is-eq tx-sender (get sponsor trial)) (is-monitor-authorized trial-id tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (get is-active participant) ERR_INVALID_STATUS)

    (map-set adverse-events event-id
      {
        trial-id: trial-id,
        participant-id: participant-id,
        severity: severity,
        description: description,
        event-height: block-height,
        resolved: false,
        resolution-notes: none
      }
    )

    (var-set adverse-event-counter event-id)
    (ok event-id)
  )
)

;; Resolve an adverse event
(define-public (resolve-adverse-event (event-id uint) (notes (string-utf8 200)))
  (let
    (
      (event (unwrap! (map-get? adverse-events event-id) ERR_EVENT_NOT_FOUND))
      (trial (unwrap! (map-get? trials (get trial-id event)) ERR_TRIAL_NOT_FOUND))
    )
    (asserts! (or (is-eq tx-sender (get sponsor trial)) (is-monitor-authorized (get trial-id event) tx-sender)) ERR_UNAUTHORIZED)

    (map-set adverse-events event-id (merge event {resolved: true, resolution-notes: (some notes)}))
    (ok true)
  )
)

;; Publish trial outcomes (once completed)
(define-public (publish-outcomes
    (trial-id uint)
    (primary-outcome (string-utf8 300))
    (secondary1 (optional (string-utf8 200)))
    (secondary2 (optional (string-utf8 200)))
    (success bool)
  )
  (let
    (
      (trial (unwrap! (map-get? trials trial-id) ERR_TRIAL_NOT_FOUND))
      (sec1 (default-to u"" secondary1))
      (sec2 (default-to u"" secondary2))
    )
    (asserts! (or (is-eq tx-sender (get sponsor trial)) (is-monitor-authorized trial-id tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq (get status trial) STATUS_COMPLETED) (is-eq (get status trial) STATUS_TERMINATED)) ERR_INVALID_STATUS)

    (map-set trial-outcomes trial-id
      {
        primary-outcome: (some primary-outcome),
        secondary-outcomes: (list sec1 sec2),
        outcome-height: block-height,
        success-indicator: (some success)
      }
    )
    (ok true)
  )
)

;; Add a monitor (authorized updater)
(define-public (add-monitor (trial-id uint) (monitor principal) (role (string-utf8 50)))
  (let ((trial (unwrap! (map-get? trials trial-id) ERR_TRIAL_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get sponsor trial)) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? trial-monitors {trial-id: trial-id, monitor: monitor})) ERR_ALREADY_EXISTS)
    (map-set trial-monitors {trial-id: trial-id, monitor: monitor}
      {role: role, added-height: block-height, is-active: true})
    (ok true)
  )
)

;; Remove or deactivate a monitor
(define-public (deactivate-monitor (trial-id uint) (monitor principal))
  (let
    (
      (trial (unwrap! (map-get? trials trial-id) ERR_TRIAL_NOT_FOUND))
      (m (unwrap! (map-get? trial-monitors {trial-id: trial-id, monitor: monitor}) ERR_UNAUTHORIZED))
    )
    (asserts! (is-eq tx-sender (get sponsor trial)) ERR_UNAUTHORIZED)
    (map-set trial-monitors {trial-id: trial-id, monitor: monitor} (merge m {is-active: false}))
    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-trial (trial-id uint))
  (map-get? trials trial-id)
)

(define-read-only (get-phase (trial-id uint) (phase uint))
  (map-get? trial-phases {trial-id: trial-id, phase: phase})
)

(define-read-only (get-participant (trial-id uint) (participant-id uint))
  (map-get? participants {trial-id: trial-id, participant-id: participant-id})
)

(define-read-only (get-participants (trial-id uint))
  (map-get? trial-participant-index trial-id)
)

(define-read-only (get-event (event-id uint))
  (map-get? adverse-events event-id)
)

(define-read-only (get-outcomes (trial-id uint))
  (map-get? trial-outcomes trial-id)
)

(define-read-only (get-monitor (trial-id uint) (monitor principal))
  (map-get? trial-monitors {trial-id: trial-id, monitor: monitor})
)

(define-read-only (get-trial-count)
  (var-get trial-counter)
)

;; Helper: is monitor authorized
(define-read-only (is-monitor-authorized (trial-id uint) (monitor principal))
  (match (map-get? trial-monitors {trial-id: trial-id, monitor: monitor})
    m (and (get is-active m) true)
    false
  )
)
