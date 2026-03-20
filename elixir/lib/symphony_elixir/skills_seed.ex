defmodule SymphonyElixir.SkillsSeed do
  @moduledoc """
  Seeds built-in skills into the LocalBoard on first startup.

  These skills are inspired by the Superpowers project and adapted
  for Symphony's autonomous agent orchestration context.
  """

  require Logger

  @built_in_skills [
    %{
      "name" => "verification",
      "description" =>
        "Use when making changes or claiming completion. Ensures every change is verified incrementally and" <>
          " completion claims are backed by fresh evidence.",
      "category" => "quality",
      "tags" => "verification,completion,incremental,evidence",
      "built_in" => true,
      "content" => """
      # Verification

      ## Iron Law
      **Verify after every logical change. No completion claims without fresh evidence.**

      ## Incremental Verification
      After each logical unit of change (one function, one file, one integration point):
      1. Save and compile — confirm no syntax errors
      2. Run the most relevant test or check
      3. If it fails, fix it NOW before moving on
      4. Only proceed to the next change after green

      Do NOT batch changes and "test everything at the end."

      ## Completion Verification
      You MUST NOT claim work is "done" or "passing" unless you have:
      1. Run the actual verification command (test, build, lint) in the current turn
      2. Read the output
      3. Confirmed success

      ### What does NOT count as verification
      - "I believe the tests pass" (without running them)
      - "This should work" (without executing)
      - Referencing test output from a previous turn

      ## Rationalization Prevention
      | Excuse | Rebuttal |
      |--------|----------|
      | "The change is trivial" | Trivial changes cause production outages. Verify. |
      | "I already verified earlier" | State may have changed. Verify again. |
      | "Verifying each step is slow" | Debugging a pile of untested changes is slower. |
      | "I'll just do one more thing first" | That's how five unverified changes become ten. Stop. |
      """
    },
    %{
      "name" => "systematic-debugging",
      "description" =>
        "Use when investigating a bug, test failure, or unexpected behavior. Enforces root cause" <>
          " investigation before fixes.",
      "category" => "debugging",
      "tags" => "debugging,root-cause,investigation",
      "built_in" => true,
      "content" => """
      # Systematic Debugging

      ## Iron Law
      **No fixes without root cause identification first.**

      ## 4-Phase Process

      ### Phase 1: Investigate
      - Reproduce the failure with a concrete command/test
      - Read error messages carefully — they usually tell you exactly what's wrong
      - Identify the component boundary where the error originates
      - Trace the bad value backward through the call stack to its origin

      ### Phase 2: Analyze
      - Form a hypothesis about the root cause
      - Identify what evidence would confirm or refute the hypothesis
      - Check related code paths for the same pattern

      ### Phase 3: Test Hypothesis
      - Make the minimal change that would fix the root cause
      - Run the failing test/command to verify the fix
      - Do NOT make multiple changes simultaneously

      ### Phase 4: Implement & Verify
      - Apply the fix
      - Run all related tests, not just the one that failed
      - Consider adding validation at multiple layers (defense in depth)

      ## Anti-Patterns to Avoid
      - Guessing at fixes without investigation
      - Changing multiple things at once
      - Fixing symptoms instead of root causes
      - Adding try/catch to suppress errors
      - "Shotgun debugging" — making random changes hoping one works
      """
    },
    %{
      "name" => "test-driven-development",
      "description" =>
        "Use when implementing new features or fixing bugs. Enforces writing tests before implementation code.",
      "category" => "workflow",
      "tags" => "tdd,testing,red-green-refactor",
      "built_in" => true,
      "content" => """
      # Test-Driven Development

      ## Iron Law
      **If you didn't watch the test fail, you don't know if it tests the right thing.**

      ## The Cycle: RED → GREEN → REFACTOR

      ### RED: Write a failing test first
      1. Write a test that describes the expected behavior
      2. Run it and watch it FAIL
      3. Verify it fails for the RIGHT reason (not a syntax error)

      ### GREEN: Make it pass with minimal code
      1. Write the simplest implementation that makes the test pass
      2. Do not over-engineer or add unrequested features
      3. Run the test and watch it PASS

      ### REFACTOR: Clean up while green
      1. Improve code quality without changing behavior
      2. Run tests after each refactoring step to ensure nothing broke
      3. Only refactor when all tests are green

      ## Rationalization Prevention
      | Excuse | Rebuttal |
      |--------|----------|
      | "Too simple to test" | Simple code with tests stays simple. Simple code without tests grows complex. |
      | "I'll write tests after" | You won't, and if you do, they'll test your implementation not your requirements. |
      | "Tests slow me down" | Debugging without tests slows you down more. |
      | "It's just a refactor" | Refactors without tests are just hope-driven development. |
      """
    },
    %{
      "name" => "plan-and-execute",
      "description" =>
        "Use when starting a new feature or multi-step change. Ensures design thinking before implementation" <>
          " and disciplined step-by-step execution.",
      "category" => "planning",
      "tags" => "design,planning,execution,checkpoints",
      "built_in" => true,
      "content" => """
      # Plan and Execute

      ## Iron Law
      **No code without a plan. No skipping steps once you have one.**

      ## Phase 1: Design

      ### Clarify Requirements
      - What exactly is being asked for? What are the acceptance criteria?
      - What edge cases and constraints exist?

      ### Explore Existing Code
      - Read the relevant modules before proposing changes
      - Understand existing patterns and conventions
      - Identify what can be reused vs. what needs to be built

      ### Outline the Approach
      Before writing implementation code, document:
      - Which files will be modified or created
      - Key data structures and component interactions
      - What tests will verify the behavior
      - At least one alternative considered and why this approach wins

      ## Phase 2: Execute

      ### Step-by-Step
      - Work through the plan one step at a time
      - Complete each step fully before moving to the next
      - Run tests/verification after each step

      ### Checkpoint After Each Step
      1. The step's specific tests pass
      2. No existing tests were broken
      3. The code compiles without warnings

      ### Handling Blockers
      - STOP — do not guess or improvise
      - Document the blocker and what was attempted
      - If the plan needs to change, update the plan first, then change the code

      ## Do NOT
      - Skip steps because they "seem unnecessary"
      - Combine multiple steps into one
      - Claim a step is done without verifying
      """
    },
    %{
      "name" => "code-review",
      "description" =>
        "Use when reviewing completed work. Provides a structured checklist for code quality review.",
      "category" => "quality",
      "tags" => "review,quality,checklist",
      "built_in" => true,
      "content" => """
      # Code Review Checklist

      ## Correctness
      - Does the code do what the issue/task requires?
      - Are edge cases handled?
      - Are error conditions handled gracefully?

      ## Code Quality
      - Is the code readable and well-organized?
      - Are variable/function names descriptive?
      - Is there unnecessary complexity that could be simplified?
      - Is there duplicated code that should be abstracted?

      ## Testing
      - Are there tests for the new behavior?
      - Do the tests cover edge cases?
      - Do the tests fail for the right reason when the code is broken?

      ## Security
      - Is user input validated and sanitized?
      - Are there any injection vulnerabilities (SQL, XSS, command)?
      - Are secrets kept out of source code?

      ## Performance
      - Are there any obvious performance issues (N+1 queries, unnecessary loops)?
      - Is the approach appropriate for the expected data scale?

      ## Conventions
      - Does the code follow the project's existing patterns?
      - Is the style consistent with the surrounding code?
      """
    },
    %{
      "name" => "scope-discipline",
      "description" =>
        "Use when working on any task with defined boundaries. Prevents scope creep and keeps work" <>
          " focused on the stated objective.",
      "category" => "workflow",
      "tags" => "scope,focus,discipline,boundaries",
      "built_in" => true,
      "content" => """
      # Scope Discipline

      ## Iron Law
      **Do what was asked. Nothing more, nothing less.**

      ## Rules

      ### Before starting any change, ask:
      - Is this change required by the issue/task description?
      - If I removed this change, would the task still be complete?
      - Am I fixing something I noticed, or something I was asked to fix?

      ### Do NOT
      - Refactor code adjacent to your change "while you're in there"
      - Add features that weren't requested, even if they seem useful
      - Fix style/formatting issues in code you didn't change
      - Upgrade dependencies unless the task requires it
      - "Improve" things you weren't asked to improve

      ### When you discover something out of scope
      - Note it as a potential follow-up issue
      - Do NOT fix it in the current task
      - If it blocks your current task, document the blocker — don't expand scope to fix it

      ## Rationalization Prevention
      | Excuse | Rebuttal |
      |--------|----------|
      | "It's a small improvement" | Small improvements compound into large, unreviewable diffs. |
      | "I'm already in this file" | Being in a file is not a mandate to change it. |
      | "Future me will thank me" | Future you will thank present you for a focused, reviewable PR. |
      """
    },
    %{
      "name" => "evidence-based-work",
      "description" =>
        "Use when making claims, gathering information, or choosing between approaches. Requires citations," <>
          " multiple sources, and concrete evidence.",
      "category" => "research",
      "tags" => "research,evidence,citations,decisions,sources",
      "built_in" => true,
      "content" => """
      # Evidence-Based Work

      ## Iron Law
      **No claims without citations. No recommendations without evidence. No conclusions from a single source.**

      ## For Factual Claims
      - Link to the original documentation, article, or code
      - If you cannot find a source, say "I could not verify this" — do not assert it as fact
      - Cross-reference multiple sources for important claims
      - When sources conflict, report the conflict explicitly
      - Prefer primary sources (official docs, RFCs, source code) over secondary (blog posts)

      ## For Technical Decisions
      1. State at least two alternatives considered
      2. For each, provide concrete evidence (benchmarks, code examples, documentation)
      3. Identify the trade-offs explicitly — nothing is free
      4. State which trade-offs matter most for THIS context and why

      ## Flag Uncertainty
      - Use explicit markers: "confirmed", "likely", "uncertain", "conflicting sources"
      - Never present speculation as established fact

      ## Anti-Patterns
      - "According to best practices..." (whose? citation needed)
      - "Industry standard" (which standard?)
      - Recommending the first approach without exploring alternatives
      - Premature performance claims without measurement
      """
    },
    %{
      "name" => "structured-reporting",
      "description" =>
        "Use when producing written deliverables, documentation, or reports. Enforces clear structure" <>
          " tailored to the audience.",
      "category" => "research",
      "tags" => "research,writing,reports,structure,audience",
      "built_in" => true,
      "content" => """
      # Structured Reporting

      ## Iron Law
      **Know your reader. Executive summary first. Evidence second. "So what?" last.**

      ## Before Writing
      - Who is the primary audience? (developer, operator, end-user, reviewer)
      - What do they already know?
      - What are they trying to do?

      ## Required Structure

      ### 1. Summary (2-3 sentences max)
      - What was investigated / what was found / what should be done

      ### 2. Key Findings (bulleted, scannable)
      - Each finding is a standalone statement backed by evidence
      - Ordered by importance, not by discovery sequence

      ### 3. Detailed Analysis
      - Organized by topic, not chronologically
      - Evidence presented with sources (links, data, code references)
      - Match the depth to the audience (developers get code, operators get commands)

      ### 4. Recommendations (actionable)
      - Concrete and actionable, not vague
      - Includes effort/complexity signal
      - Distinguishes "must do" from "should consider"

      ## Anti-Patterns
      - Stream-of-consciousness writing ("First I looked at X, then I tried Y...")
      - Burying the conclusion at the end
      - Writing for yourself instead of the reader
      - Code snippets that don't work when copied
      """
    },
    %{
      "name" => "information-design",
      "description" =>
        "Use when organizing information, navigation, or page structure. Ensures content is structured by" <>
          " user mental models with manageable cognitive load.",
      "category" => "information-architecture",
      "tags" => "ia,hierarchy,navigation,cognitive-load,organization",
      "built_in" => true,
      "content" => """
      # Information Design

      ## Iron Law
      **Organize by what users look for. Never ask them to hold more than they can process.**

      ## Content Hierarchy
      - Group content by what users are trying to accomplish, not by system internals
      - Navigation labels use the user's language, not jargon
      - Most common tasks are easiest to find
      - Show summary first, details on demand (progressive disclosure)
      - Every piece of content has a "home" — orphaned content is a bug

      ## Cognitive Load Management
      - No more than 5-9 items in any ungrouped list (7±2 rule)
      - Group larger lists into labeled categories
      - Every form field has a sensible default when possible
      - Show available options rather than requiring recall
      - One primary action per view — secondary actions are visually subdued

      ## Visual Hierarchy
      - Visual weight (size, color, position) matches actual importance
      - Related items are visually grouped; unrelated items are separated
      - Destructive actions require deliberate effort (not one accidental click)

      ## Anti-Patterns
      - Flat lists of 20+ items with no grouping
      - Navigation that mirrors the codebase folder structure
      - Showing all settings/options at once ("the cockpit problem")
      - Equal visual weight for everything (means nothing is important)
      """
    },
    %{
      "name" => "ui-design",
      "description" =>
        "Use when designing flows, forms, layouts, or visual components. Ensures user-goal-driven design" <>
          " with consistent spatial language.",
      "category" => "ux",
      "tags" => "ux,user-journey,flows,layout,spacing,css",
      "built_in" => true,
      "content" => """
      # UI Design

      ## Iron Law
      **State the user's goal before choosing any layout. No magic numbers in spacing.**

      ## User Journey
      - Before designing, write: "The user wants to [verb] [object] so that [outcome]."
      - Map the happy path — minimum steps to goal
      - Handle real paths: empty states, error states, loading states, edge cases (0 items, 1000 items)
      - Every click/tap/keystroke is a cost — minimize friction
      - Prefer smart defaults, inline editing, progressive disclosure

      ## Spatial Consistency
      - Use the project's spacing scale (4px, 8px, 12px, 16px, 24px) — no arbitrary values
      - Elements with the same role align to the same grid
      - Navigation always in the same position; primary actions always in the same place
      - Whitespace is intentional: more between groups, less within groups
      - Consistent padding within component types

      ## Responsive Behavior
      - Components reflow predictably at breakpoints
      - Nothing overflows, overlaps, or disappears unexpectedly
      - Touch targets are at least 44x44px on mobile

      ## Anti-Patterns
      - Designing around API fields instead of user goals
      - Ignoring empty/error/loading states
      - `margin-top: 13px` (why 13? use the scale)
      - Layout that works at exactly one screen size
      """
    },
    %{
      "name" => "extract-architecture",
      "description" =>
        "Use when extracting system architecture from a codebase. Produces a structured KB note" <>
          " documenting components, boundaries, data flow, and tech stack.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,architecture,documentation,kb",
      "built_in" => true,
      "content" => """
      # Extract Architecture

      ## Goal
      Produce a structured KB note that documents the system's architecture so that anyone — human or agent —
      can understand the system's shape without reading every file.

      ## Process

      ### 1. Identify the system boundary
      - What is the top-level application or service?
      - What are its entry points (CLI, HTTP, message queue, cron)?
      - What external systems does it talk to (databases, APIs, file systems)?

      ### 2. Map the major components
      For each component document:
      - **Name** — the module, namespace, or service name
      - **Responsibility** — one sentence: what does it own?
      - **Key interfaces** — public functions, endpoints, or messages it exposes
      - **Dependencies** — what it calls or imports

      ### 3. Document the data flow
      - Trace the path of a typical request from entry point to response
      - Identify where state is stored (database, ETS, GenServer state, files)
      - Note any async boundaries (message queues, background jobs, pub/sub)

      ### 4. Record the tech stack
      - Language(s) and versions
      - Frameworks and key libraries
      - Infrastructure assumptions (OS, runtime, container, cloud services)

      ## Output Format
      Write a markdown note with YAML frontmatter:
      ```
      ---
      tags:
        - architecture
        - extraction
      date: YYYY-MM-DD
      source: codebase analysis
      product: <product-name>
      ---
      ```

      Sections: Overview, Components, Data Flow, Tech Stack, Key Decisions (if discoverable from comments/docs).

      ## What NOT to include
      - Line-by-line code explanations (link to files instead)
      - Opinions about what should change (that's a separate issue)
      - Speculative future architecture
      """
    },
    %{
      "name" => "extract-business-logic",
      "description" =>
        "Use when extracting business rules and domain logic from a codebase. Produces a structured KB note" <>
          " cataloging validation rules, state machines, invariants, and domain concepts.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,business-logic,domain,rules,kb",
      "built_in" => true,
      "content" => """
      # Extract Business Logic

      ## Goal
      Produce a structured KB note that catalogs the business rules embedded in the code — the "why" behind
      conditionals, validations, and state transitions.

      ## Process

      ### 1. Identify domain entities
      - What are the core data structures (models, schemas, types)?
      - What are their required fields, defaults, and constraints?
      - How do they relate to each other (ownership, references, hierarchies)?

      ### 2. Catalog validation rules
      For each entity, document:
      - **Field validations** — required, format, range, uniqueness
      - **Cross-field rules** — "if X then Y must be Z"
      - **Business invariants** — conditions that must always be true
      - **Where enforced** — file:line references

      ### 3. Map state machines and transitions
      - What states can each entity be in?
      - What transitions are allowed? What triggers them?
      - What side effects occur on transition (notifications, cascading updates)?
      - Are there guard conditions on transitions?

      ### 4. Document domain-specific calculations
      - Pricing, scoring, ranking, or scheduling logic
      - Formulas with their business meaning, not just the math
      - Edge cases and special handling

      ### 5. Record authorization rules
      - Who can do what? (roles, ownership, permissions)
      - Where are these checks enforced?

      ## Output Format
      Write a markdown note with YAML frontmatter:
      ```
      ---
      tags:
        - business-logic
        - extraction
      date: YYYY-MM-DD
      source: codebase analysis
      product: <product-name>
      ---
      ```

      Sections: Domain Entities, Validation Rules, State Machines, Calculations, Authorization.
      Use tables for rules catalogs. Include file:line references.

      ## What NOT to include
      - Implementation details (how the code does it) — focus on WHAT rule is enforced and WHY
      - Infrastructure logic (caching, retry, logging) — that's architecture
      """
    },
    %{
      "name" => "extract-constraints",
      "description" =>
        "Use when extracting technical constraints and limitations from a codebase. Produces a structured KB" <>
          " note documenting performance limits, security boundaries, compatibility requirements, and" <>
          " operational constraints.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,constraints,limits,security,kb",
      "built_in" => true,
      "content" => """
      # Extract Technical Constraints

      ## Goal
      Produce a structured KB note that documents the hard limits, boundaries, and non-negotiable
      requirements baked into the system — the things you cannot change without consequences.

      ## Process

      ### 1. Performance constraints
      - Timeouts (HTTP, database, GenServer calls, external API)
      - Rate limits (inbound and outbound)
      - Size limits (file uploads, payload sizes, batch sizes, pagination)
      - Concurrency limits (pool sizes, max connections, worker counts)
      - Where these are configured (hardcoded vs. configurable)

      ### 2. Security boundaries
      - Sandboxing or isolation mechanisms
      - Input sanitization points
      - Authentication and session constraints (token expiry, refresh rules)
      - Secrets management (where stored, how rotated)
      - CORS, CSP, or network policies

      ### 3. Compatibility requirements
      - Minimum runtime/language versions
      - OS or platform dependencies
      - Browser compatibility targets
      - API versioning contracts (what can't break)
      - Data format constraints (encoding, schema versions)

      ### 4. Operational constraints
      - Deployment requirements (zero-downtime, migration ordering)
      - Monitoring assumptions (what metrics must exist)
      - Backup and recovery expectations
      - Licensing restrictions on dependencies

      ## Output Format
      Write a markdown note with YAML frontmatter:
      ```
      ---
      tags:
        - constraints
        - extraction
      date: YYYY-MM-DD
      source: codebase analysis
      product: <product-name>
      ---
      ```

      Sections: Performance, Security, Compatibility, Operational.
      Use tables: Constraint | Value | Where Configured | Impact of Violation.

      ## What NOT to include
      - Soft preferences or style choices — only hard constraints
      - Recommendations for changes (that's a separate issue)
      """
    },
    %{
      "name" => "extract-workflows",
      "description" =>
        "Use when extracting process workflows from a codebase. Produces a structured KB note documenting" <>
          " how data and work flow through the system — pipelines, lifecycles, and multi-step processes.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,workflows,processes,lifecycle,kb",
      "built_in" => true,
      "content" => """
      # Extract Process Workflows

      ## Goal
      Produce a structured KB note that documents the end-to-end processes in the system — how things move
      from start to finish, who/what is involved at each step, and what triggers transitions.

      ## Process

      ### 1. Identify major workflows
      - User-facing flows (create, edit, delete, search, import/export)
      - System flows (startup, shutdown, migration, sync, scheduled jobs)
      - Integration flows (webhook handling, API consumption, event processing)
      - Error/recovery flows (retry, fallback, manual intervention)

      ### 2. For each workflow, document:
      - **Trigger** — what starts the workflow (user action, timer, event, API call)
      - **Steps** — ordered sequence with:
        - Actor (user, system, external service)
        - Action (what happens)
        - Input/output (what data flows in and out)
        - Decision points (branches, conditions)
      - **Terminal states** — success, failure, timeout, cancelled
      - **Side effects** — notifications, logging, metrics, cascading updates

      ### 3. Map async and parallel flows
      - Which steps happen synchronously vs. asynchronously?
      - Are there background jobs, message queues, or pub/sub involved?
      - What happens if an async step fails? (retry, dead letter, alert)

      ### 4. Document orchestration
      - Is there a central orchestrator or is it event-driven/choreographed?
      - Where is the workflow state tracked?
      - Can workflows be paused, resumed, or cancelled?

      ## Output Format
      Write a markdown note with YAML frontmatter:
      ```
      ---
      tags:
        - workflows
        - extraction
      date: YYYY-MM-DD
      source: codebase analysis
      product: <product-name>
      ---
      ```

      Sections: one section per major workflow.
      Use numbered step lists. Include file:line references for key orchestration points.
      Mermaid diagrams are encouraged for complex flows.

      ## What NOT to include
      - UI layout details (that's architecture/design)
      - Individual function implementations (link to code instead)
      """
    },
    %{
      "name" => "extract-product-overview",
      "description" =>
        "Use when extracting a product or project overview from a codebase. Produces a structured KB note" <>
          " with feature inventory, completeness status, and project structure.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,product,features,overview,kb",
      "built_in" => true,
      "content" => """
      # Extract Product/Project Overview

      ## Goal
      Produce a structured KB note that gives a complete picture of what the product does, what features
      exist, how complete they are, and how the project is organized.

      ## Process

      ### 1. Product identity
      - What is this product/project? One-paragraph description.
      - Who is it for? (target users/audience)
      - What problem does it solve?
      - How is it deployed/distributed?

      ### 2. Feature inventory
      For each feature, document:
      - **Feature name** — clear, user-facing name
      - **Description** — what it does in one sentence
      - **Status** — one of: complete, partial, stub, planned, deprecated
      - **Evidence for status**:
        - Complete: has tests, handles edge cases, has UI (if applicable)
        - Partial: core logic works but missing tests, error handling, or UI polish
        - Stub: interface exists but implementation is placeholder or TODO
        - Planned: referenced in code/comments but not implemented
        - Deprecated: marked for removal or replaced by alternative
      - **Key files** — where the feature lives (entry points, not every file)

      ### 3. Project structure
      - Top-level directory layout and what each directory owns
      - Configuration files and their purpose
      - Test organization and coverage areas
      - Build/deploy artifacts

      ### 4. Dependencies and integrations
      - External services the product integrates with
      - Key library dependencies and what they provide
      - Internal shared modules/packages

      ### 5. Known gaps and tech debt
      - TODOs and FIXMEs found in the code (grouped by area)
      - Missing test coverage areas
      - Commented-out code or dead code paths
      - Hardcoded values that should be configurable

      ## Output Format
      Write a markdown note with YAML frontmatter:
      ```
      ---
      tags:
        - product-overview
        - extraction
      date: YYYY-MM-DD
      source: codebase analysis
      product: <product-name>
      ---
      ```

      Sections: Product Identity, Feature Inventory (as a table), Project Structure, Dependencies, Known Gaps.
      Feature inventory table: Feature | Status | Description | Key Files.

      ## What NOT to include
      - Detailed code walkthroughs (link to files)
      - Subjective quality judgments — report facts (has tests / no tests, not "poorly tested")
      """
    },
    # ── Product Hardening Skills (scan + apply pairs) ──────────────
    #
    # Each hardening step has two skills:
    #   *-scan: Analyze only, output structured findings as JSON. No code changes.
    #   *-apply: Read accepted findings, apply only those. Make code changes.
    #
    # Findings JSON format (written to FINDINGS_<scan-type>.json in workspace):
    # [{"id": "F1", "title": "...", "severity": "high|medium|low",
    #   "description": "...", "files": ["path/to/file.ex:42"], "fix_hint": "..."}]
    # Each scan writes to a UNIQUE filename to avoid overwriting parallel scans.

    # ── Lint & Format ──
    %{
      "name" => "hardening-lint-format-scan",
      "description" => "SCAN: Detect lint and format violations across all subprojects. No code changes —" <>
        " output structured findings.",
      "category" => "hardening",
      "tags" => "hardening,lint,format,scan",
      "built_in" => true,
      "content" => """
      # Lint & Format — Scan

      ## Mode: SCAN ONLY
      You MUST NOT make any code changes. Your job is to analyze and report findings.

      ## Goal
      Detect all lint and format violations across every subproject. Output structured findings for human review.

      ## Process

      ### 1. Detect the tech stack for EACH subproject
      Walk the product's project directories. For each one, identify:
      - **Elixir**: `mix.exs` → run `mix format --check-formatted`, `mix credo --strict`
      - **Python**: `pyproject.toml`/`setup.py` → run `ruff check` (no --fix), `ruff format --check`
      - **TypeScript/JavaScript**: `package.json` → run `eslint` (no --fix), `prettier --check`
      - **Go**: `go.mod` → run `gofmt -l`, `golangci-lint run`
      - **Rust**: `Cargo.toml` → run `cargo fmt --check`, `cargo clippy`
      - **Ruby**: `Gemfile` → run `rubocop --format json`

      ### 2. Collect violations
      For each violation, record: file, line, rule, message, severity, auto-fixable or manual.

      ### 3. Skip subprojects with no linter config — note them in the report.

      ## Output
      Write `FINDINGS_lint-format.json` to the workspace root with this format:
      ```json
      [
        {"id": "F1", "title": "ruff: unused import os (main.py:3)", "severity": "low",
         "description": "Unused import `os` in main.py line 3.", "files": ["main.py:3"],
         "fix_hint": "Remove `import os`", "category": "lint", "auto_fixable": true},
        ...
      ]
      ```
      Each finding = one violation or a small group of related violations in the same file.

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-lint-format-apply",
      "description" => "APPLY: Fix accepted lint and format violations. Only apply findings approved in the gate.",
      "category" => "hardening",
      "tags" => "hardening,lint,format,apply",
      "built_in" => true,
      "content" => """
      # Lint & Format — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      Read the accepted findings from the gate decision. Apply ONLY those fixes.
      Do NOT fix anything that was not accepted.

      ## Process
      1. Read the accepted finding IDs from the pipeline context
      2. For each accepted finding, apply the fix (run formatter/linter with --fix on specific files, or fix manually)
      3. Verify: re-run linters on affected files, run test suite
      4. Write a brief report of what was applied

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT fix findings that were rejected/discarded
      - Do NOT change logic or behavior — style/format only
      - Do NOT add new linter dependencies
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Dead Code ──
    %{
      "name" => "hardening-dead-code-scan",
      "description" => "SCAN: Find dead code, unused imports, unreachable branches across all subprojects." <>
        " No removals — output findings.",
      "category" => "hardening",
      "tags" => "hardening,dead-code,unused,scan",
      "built_in" => true,
      "content" => """
      # Dead Code Removal — Scan

      ## Mode: SCAN ONLY
      You MUST NOT delete or modify any code. Analyze and report findings only.

      ## Goal
      Find all unused code across every subproject: unused functions, modules, imports, variables,
      unreachable branches, stale files.

      ## Process
      ### 1. Detect and scan each subproject
      - **Elixir**: `mix xref graph --format stats`, check for unused functions/modules,
        stale `alias`/`import`/`require`
      - **Python**: `vulture`, `ruff` unused import rules, `autoflake --check`
      - **TypeScript/JavaScript**: `ts-prune`, `eslint` no-unused-vars/imports, `knip`
      - **Go**: `deadcode`, compiler unused var/import errors
      - **Rust**: compiler dead_code warnings
      - **Ruby**: `debride`, unused method detection

      ### 2. For each item found, assess:
      - Is it truly unused or called via dynamic dispatch/reflection/macros?
      - Is it a public API that may be called externally?
      - Is it a callback implementation (GenServer, Plug, etc.)?
      - Confidence level: high (definitely dead) vs. medium (probably dead) vs. low (uncertain)

      ## Output
      Write `FINDINGS_dead-code.json`:
      ```json
      [
        {"id": "F1", "title": "Unused function: MyModule.old_helper/2", "severity": "medium",
         "description": "Private function never called. Last modified 6 months ago.", "files": ["lib/my_module.ex:42"],
         "fix_hint": "Delete function definition (lines 42-55)", "category": "dead-code", "confidence": "high"}
      ]
      ```

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-dead-code-apply",
      "description" => "APPLY: Remove accepted dead code findings. Only remove items approved in the gate.",
      "category" => "hardening",
      "tags" => "hardening,dead-code,unused,apply",
      "built_in" => true,
      "content" => """
      # Dead Code Removal — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. Remove ONLY the dead code items that were accepted
      4. Run the full test suite to verify nothing broke
      5. Confirm compilation succeeds with no new warnings
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Dependency Audit ──
    %{
      "name" => "hardening-dependency-audit-scan",
      "description" => "SCAN: Audit dependencies for vulnerabilities, outdated versions, unused packages." <>
        " No changes — output findings.",
      "category" => "hardening",
      "tags" => "hardening,dependencies,audit,scan",
      "built_in" => true,
      "content" => """
      # Dependency Audit — Scan

      ## Mode: SCAN ONLY
      Do NOT update, remove, or modify any dependencies. Analyze and report only.

      ## Process
      ### 1. For each subproject, detect and audit
      - **Elixir**: `mix hex.audit`, `mix deps.unlock --check-unused`, `mix hex.outdated`
      - **Python**: `pip-audit`, `safety check`, `pip list --outdated`
      - **Node/TS/JS**: `npm audit`, `npm outdated`, `depcheck`
      - **Go**: `govulncheck`, `go list -m -u all`
      - **Rust**: `cargo audit`, `cargo outdated`
      - **Ruby**: `bundle audit`, `bundle outdated`

      ### 2. Categorize each finding
      - **Vulnerability**: CVE ID, severity, affected version, patched version
      - **Unused**: declared but never imported/used
      - **Outdated**: current vs latest, breaking changes in changelog
      - **Major update**: flag separately — requires manual review

      ## Output
      Write `FINDINGS_dep-audit.json`:
      ```json
      [
        {"id": "F1", "title": "CVE-2024-1234 in requests 2.28.0", "severity": "high",
         "description": "Remote code execution via crafted URL. Fix: upgrade to 2.31.0+",
         "files": ["requirements.txt"], "fix_hint": "Update requests to >=2.31.0", "category": "vulnerability"},
        {"id": "F2", "title": "Unused dep: left-pad", "severity": "low",
         "description": "Declared in package.json but never imported.", "files": ["package.json"],
         "fix_hint": "Remove from dependencies", "category": "unused-dep"}
      ]
      ```

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-dependency-audit-apply",
      "description" => "APPLY: Fix accepted dependency findings. Only update/remove deps approved in the gate.",
      "category" => "hardening",
      "tags" => "hardening,dependencies,audit,apply",
      "built_in" => true,
      "content" => """
      # Dependency Audit — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. For each accepted finding: update vulnerable dep, remove unused dep, or bump outdated dep
      4. Do NOT auto-upgrade major versions unless the finding was specifically accepted
      5. Run full test suite after all changes
      6. Re-run audit tools to confirm clean state
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Security Scan ──
    %{
      "name" => "hardening-security-scan-scan",
      "description" => "SCAN: Find security vulnerabilities (OWASP top 10, secrets, injection) across all" <>
        " subprojects. No fixes — output findings.",
      "category" => "hardening",
      "tags" => "hardening,security,owasp,scan",
      "built_in" => true,
      "content" => """
      # Security Scan — Scan

      ## Mode: SCAN ONLY
      Do NOT fix any issues. Analyze and report findings only.

      ## Process
      ### 1. Run security tools per subproject
      - **Elixir**: `sobelow --config`, raw SQL queries, path traversal
      - **Python**: `bandit`, `semgrep --config=p/owasp-top-ten`
      - **TypeScript/JavaScript**: `eslint-plugin-security`, `semgrep`, XSS in templates
      - **Go**: `gosec`, `semgrep`
      - **General**: `gitleaks` / `trufflehog` for hardcoded secrets

      ### 2. Manual code review for
      - Injection (SQL, command, template), path traversal, auth/authz gaps
      - XSS, CSRF, secrets in code, insecure defaults, mass assignment

      ### 3. Rate each finding: critical / high / medium / low

      ## Output
      Write `FINDINGS_security-scan.json`:
      ```json
      [
        {"id": "F1", "title": "SQL injection in user search", "severity": "critical",
         "description": "User input concatenated into SQL query without parameterization.",
         "files": ["lib/search.ex:28"], "fix_hint": "Use parameterized query with $1 placeholder",
         "category": "injection"}
      ]
      ```

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-security-scan-apply",
      "description" => "APPLY: Fix accepted security findings. Only fix vulnerabilities approved in the gate.",
      "category" => "hardening",
      "tags" => "hardening,security,owasp,apply",
      "built_in" => true,
      "content" => """
      # Security Scan — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. Fix ONLY accepted security issues: add sanitization, replace secrets, add auth checks, escape output
      4. Do NOT suppress warnings — fix the underlying issue
      5. Re-run security scanners on affected files
      6. Run the test suite
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── DRY Analysis ──
    %{
      "name" => "hardening-dry-analysis-scan",
      "description" => "SCAN: Find duplicated code and patterns across all subprojects." <>
        " No refactoring — output findings.",
      "category" => "hardening",
      "tags" => "hardening,dry,duplication,scan",
      "built_in" => true,
      "content" => """
      # DRY Analysis — Scan

      ## Mode: SCAN ONLY
      Do NOT refactor or extract code. Analyze and report duplication findings only.

      ## Process
      - Find repeated code blocks (3+ similar lines in multiple places)
      - Find copy-pasted functions with minor variations
      - Find repeated test setup/teardown logic
      - Find duplicated constants and magic numbers
      - Check across subprojects for shared logic candidates
      - Only flag 3+ occurrences OR likely-to-grow duplication

      ## Output
      Write `FINDINGS_dry-analysis.json`:
      ```json
      [
        {"id": "F1", "title": "Duplicated HTTP client setup (4 occurrences)", "severity": "medium",
         "description": "Same 12-line HTTP client initialization in 4 modules.",
         "files": ["lib/api_a.ex:10", "lib/api_b.ex:15", "lib/api_c.ex:8", "lib/api_d.ex:12"],
         "fix_hint": "Extract into shared HttpClient module", "category": "duplication", "occurrences": 4}
      ]
      ```
      """
    },
    %{
      "name" => "hardening-dry-analysis-apply",
      "description" => "APPLY: Extract and refactor accepted duplication findings. Only fix approved items.",
      "category" => "hardening",
      "tags" => "hardening,dry,duplication,apply",
      "built_in" => true,
      "content" => """
      # DRY Analysis — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. For each accepted finding: extract shared function/module, update all callers
      4. Name extracted functions by WHAT they do, not WHERE they came from
      5. Run the full test suite after each extraction
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Error Handling ──
    %{
      "name" => "hardening-error-handling-scan",
      "description" => "SCAN: Find error handling issues (bare rescues, swallowed errors) across all" <>
        " subprojects. No fixes — output findings.",
      "category" => "hardening",
      "tags" => "hardening,errors,handling,scan",
      "built_in" => true,
      "content" => """
      # Error Handling Audit — Scan

      ## Mode: SCAN ONLY
      Do NOT fix any error handling. Analyze and report findings only.

      ## Process
      Audit per tech stack:
      - **Elixir**: bare `rescue`, `try/catch` returning `:ok` on failure, missing `{:error, _}` in `with` chains
      - **Python**: bare `except:` or `except Exception:` that pass, missing error logging
      - **TypeScript/JavaScript**: empty `catch {}`, `.catch(() => {})`, unhandled promise rejections
      - **Go**: `_ = err` or unchecked error returns
      - **Rust**: `.unwrap()` in library code

      ## Output
      Write `FINDINGS_error-handling.json`:
      ```json
      [
        {"id": "F1", "title": "Bare rescue in DataLoader.fetch/1", "severity": "high",
         "description": "Bare rescue catches all errors and returns :ok, hiding failures.",
         "files": ["lib/data_loader.ex:45"],
         "fix_hint": "Pattern match on specific error types, log unexpected errors",
         "category": "swallowed-error"}
      ]
      ```

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-error-handling-apply",
      "description" => "APPLY: Fix accepted error handling findings. Only fix approved items.",
      "category" => "hardening",
      "tags" => "hardening,errors,handling,apply",
      "built_in" => true,
      "content" => """
      # Error Handling Audit — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. Fix ONLY accepted issues: replace bare rescues, add error logging, add missing error clauses
      4. Do NOT add error handling for impossible cases
      5. Do NOT change the error handling strategy (exceptions vs result tuples)
      6. Run the test suite
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Type Safety ──
    %{
      "name" => "hardening-type-safety-scan",
      "description" => "SCAN: Find missing type annotations and type errors across all subprojects." <>
        " No changes — output findings.",
      "category" => "hardening",
      "tags" => "hardening,types,typespecs,scan",
      "built_in" => true,
      "content" => """
      # Type Safety Audit — Scan

      ## Mode: SCAN ONLY
      Do NOT add or modify types. Analyze and report findings only.

      ## Process per tech stack
      - **Elixir**: find public functions without `@spec`, run `dialyzer` if configured
      - **Python**: run `mypy` / `pyright`, find functions without type hints
      - **TypeScript**: check for `any` types, missing return types, strict mode violations
      - **Go**: find `interface{}` / `any` that could be tightened
      - **Rust**: find unnecessary `.unwrap()`, loose generic bounds

      ## Output
      Write `FINDINGS_type-safety.json`:
      ```json
      [
        {"id": "F1", "title": "Missing @spec for MyModule.process/2", "severity": "low",
         "description": "Public function without typespec. Takes a map and string,
           returns {:ok, map} | {:error, term}.",
         "files": ["lib/my_module.ex:30"],
         "fix_hint": "@spec process(map(), String.t()) :: {:ok, map()} | {:error, term()}",
         "category": "missing-type"}
      ]
      ```

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-type-safety-apply",
      "description" => "APPLY: Add accepted type annotations and fix accepted type errors. Only apply approved items.",
      "category" => "hardening",
      "tags" => "hardening,types,typespecs,apply",
      "built_in" => true,
      "content" => """
      # Type Safety Audit — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. Add specs/annotations or fix type errors for ONLY accepted findings
      4. Do NOT change runtime behavior to satisfy the type checker
      5. Run the type checker and test suite
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Test Style ──
    %{
      "name" => "hardening-test-style-scan",
      "description" => "SCAN: Find test style inconsistencies across all subprojects. No changes — output findings.",
      "category" => "hardening",
      "tags" => "hardening,tests,style,scan",
      "built_in" => true,
      "content" => """
      # Test Style & Consistency — Scan

      ## Mode: SCAN ONLY
      Do NOT modify any test files. Analyze and report findings only.

      ## Process
      - Naming: test names describe behavior or implementation?
      - Setup: consistent use of setup/teardown patterns?
      - Assertions: consistent assertion style?
      - Organization: tests grouped by module/feature?
      - Fixtures: consistent data creation or ad-hoc?
      - Flaky patterns: shared state, time-dependent, order-dependent?

      ## Output
      Write `FINDINGS_test-style.json`:
      ```json
      [
        {"id": "F1", "title": "Inconsistent test naming in test/api_test.exs", "severity": "low",
         "description": "5 tests use 'test X' style, rest use 'describe/it' style.",
         "files": ["test/api_test.exs:12", "test/api_test.exs:28"],
         "fix_hint": "Rename to match project convention: describe + test blocks", "category": "naming"}
      ]
      ```

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-test-style-apply",
      "description" => "APPLY: Fix accepted test style findings. Only fix approved items.",
      "category" => "hardening",
      "tags" => "hardening,tests,style,apply",
      "built_in" => true,
      "content" => """
      # Test Style & Consistency — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. Fix ONLY accepted style issues: rename tests, extract setup, standardize assertions
      4. Do NOT change what tests verify — only style and organization
      5. Do NOT delete tests
      6. Run the full test suite — all tests must still pass
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Infrastructure ──
    %{
      "name" => "hardening-infrastructure-scan",
      "description" => "SCAN: Find infrastructure issues (CI/CD, Docker, config, .gitignore) across all" <>
        " subprojects. No changes — output findings.",
      "category" => "hardening",
      "tags" => "hardening,infrastructure,ci,docker,scan",
      "built_in" => true,
      "content" => """
      # Infrastructure Review — Scan

      ## Mode: SCAN ONLY
      Do NOT modify any infrastructure files. Analyze and report findings only.

      ## Process
      - **CI/CD**: deprecated actions, missing caching, redundant steps, missing test stages
      - **Docker**: missing multi-stage builds, secrets in layers, `.dockerignore` gaps
      - **Build scripts**: dead targets, missing help text, inconsistent conventions
      - **Config**: hardcoded env values, missing sensible defaults
      - **Git**: `.gitignore` gaps (build artifacts, secrets, IDE files)

      ## Output
      Write `FINDINGS_infra-review.json`:
      ```json
      [
        {"id": "F1", "title": "No dependency caching in CI pipeline", "severity": "medium",
         "description": ".gitlab-ci.yml runs pip install on every job without caching.",
         "files": [".gitlab-ci.yml:15"], "fix_hint": "Add pip cache key based on requirements.txt hash",
         "category": "ci-performance"}
      ]
      ```

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-infrastructure-apply",
      "description" => "APPLY: Fix accepted infrastructure findings. Only fix approved items.",
      "category" => "hardening",
      "tags" => "hardening,infrastructure,ci,docker,apply",
      "built_in" => true,
      "content" => """
      # Infrastructure Review — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. Fix ONLY accepted issues in CI/CD, Docker, build scripts, config, .gitignore
      4. Do NOT change deployment targets, secrets, or branch policies
      5. Verify build/CI scripts still work (dry-run if possible)
      6. Run the test suite
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Playwright E2E ──
    %{
      "name" => "hardening-playwright-e2e-scan",
      "description" => "SCAN: Find broken/missing Playwright E2E tests. Mark N/A if no frontend." <>
        " No fixes — output findings.",
      "category" => "hardening",
      "tags" => "hardening,playwright,e2e,scan",
      "built_in" => true,
      "content" => """
      # Frontend E2E (Playwright) — Scan

      ## Mode: SCAN ONLY
      Do NOT fix or add tests. Analyze and report findings only.

      ## Applicability Check
      First, determine if the product has a frontend:
      - Look for Playwright config, test directories, `@playwright/test` in deps
      - Look for HTML templates, React/Vue/Svelte/Angular components
      - If NO frontend: write `FINDINGS_playwright-e2e.json` with a single entry:
        `{"id": "F0", "title": "N/A — no frontend detected", "severity": "info",
        "description": "No frontend or E2E tests found.", "files": [], "category": "not-applicable"}`

      ## Process (if applicable)
      1. Run `npx playwright test` — collect all failures
      2. List all user-facing pages/flows, map existing tests to flows
      3. Identify untested critical paths

      ## Output
      Write `FINDINGS_playwright-e2e.json`:
      ```json
      [
        {"id": "F1", "title": "Broken test: login flow (timeout on submit)", "severity": "high",
         "description": "test/e2e/login.spec.ts:15 — times out clicking submit button.",
         "files": ["test/e2e/login.spec.ts:15"],
         "fix_hint": "Update selector from #login-btn to [data-testid=login-submit]",
         "category": "broken-test"},
        {"id": "F2", "title": "Missing E2E: user settings page", "severity": "medium",
         "description": "No tests cover the /settings page (CRUD operations).",
         "files": [], "fix_hint": "Add settings.spec.ts covering view/edit/save flow", "category": "missing-coverage"}
      ]
      ```

      ## Rules
      - Before running any commands, install project dependencies first (npm install, npx playwright install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-playwright-e2e-apply",
      "description" => "APPLY: Fix/add accepted Playwright E2E tests. Only apply approved findings.",
      "category" => "hardening",
      "tags" => "hardening,playwright,e2e,apply",
      "built_in" => true,
      "content" => """
      # Frontend E2E (Playwright) — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, npx playwright install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. Fix broken tests and add missing tests ONLY for accepted findings
      4. Follow existing test patterns and conventions
      5. Each test must be independent (no shared state)
      6. Run the full E2E suite — all tests must pass
      7. Tests must be stable (run twice, same result)
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Test Coverage ──
    %{
      "name" => "hardening-test-coverage-scan",
      "description" => "SCAN: Measure test coverage, find gaps and duplicates across all subprojects." <>
        " No changes — output findings.",
      "category" => "hardening",
      "tags" => "hardening,coverage,testing,scan",
      "built_in" => true,
      "content" => """
      # Test Coverage Audit — Scan

      ## Mode: SCAN ONLY
      Do NOT add, remove, or modify tests. Analyze and report findings only.
      This runs LAST because prior phases may have changed code and tests.

      ## Process
      ### 1. Measure coverage per subproject
      - **Elixir**: `mix test --cover`, **Python**: `pytest --cov`, **TS/JS**: `jest --coverage`
      - **Go**: `go test -coverprofile`, **Rust**: `cargo tarpaulin`

      ### 2. Identify gaps
      - Modules/files with < 80% line coverage
      - Critical paths with zero coverage (business logic, error handling, state transitions)
      - Focus on behavioral coverage, not line count

      ### 3. Identify duplicates
      - Tests verifying exact same behavior (same setup, same assertion)
      - Integration tests duplicating unit test coverage

      ## Output
      Write `FINDINGS_test-coverage.json`:
      ```json
      [
        {"id": "F1", "title": "Zero coverage: PaymentProcessor.refund/2", "severity": "high",
         "description": "Critical business logic with no tests. Handles refund calculation and validation.",
         "files": ["lib/payment_processor.ex:80-120"],
         "fix_hint": "Add unit tests for happy path, partial refund, and error cases",
         "category": "coverage-gap"},
        {"id": "F2", "title": "Duplicate tests: user creation (3 identical)", "severity": "low",
         "description": "test/user_test.exs:10, test/integration/user_test.exs:5,
           test/api/user_test.exs:20 all test the same create path.",
         "files": ["test/user_test.exs:10", "test/integration/user_test.exs:5"],
         "fix_hint": "Keep test/user_test.exs:10 (most focused), remove others", "category": "duplicate-test"}
      ]
      ```

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Do NOT skip because a tool is missing — install it
      """
    },
    %{
      "name" => "hardening-test-coverage-apply",
      "description" => "APPLY: Add missing tests and remove duplicates for accepted findings." <>
        " Only apply approved items.",
      "category" => "hardening",
      "tags" => "hardening,coverage,testing,apply",
      "built_in" => true,
      "content" => """
      # Test Coverage Audit — Apply

      ## Mode: APPLY ACCEPTED FINDINGS ONLY
      1. Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      2. Read accepted finding IDs from pipeline context
      3. For coverage gaps: add unit tests following existing patterns
      4. For duplicates: remove the less-focused duplicate, keep the more precise one
      5. Do NOT remove tests that look similar but test different edge cases
      6. Run full test suite — zero failures
      7. Re-measure coverage — report before/after
      - Do NOT skip because a tool is missing — install it
      """
    },

    # ── Pipeline Summary (unchanged — single skill, no scan/apply split) ──
    %{
      "name" => "hardening-pipeline-summary",
      "description" =>
        "Summarize the entire Product Health & Hardening pipeline run: what was done," <>
          " what was accepted/rejected, final state.",
      "category" => "hardening",
      "tags" => "hardening,summary,report,overview",
      "built_in" => true,
      "content" => """
      # Pipeline Summary Report

      ## Goal
      Produce a comprehensive summary of everything done during the Product Health & Hardening pipeline run.

      ## Process

      ### 1. Gather results from all predecessor phases
      Read the workspace for each completed issue in this pipeline run. Look for:
      - Reports and FINDINGS.json from each scan agent
      - Gate decisions showing which findings were accepted/rejected
      - Git diffs or commit logs from apply agents
      - Test results before and after

      ### 2. Write the summary with these sections

      #### Executive Summary
      - One paragraph: what was the overall health of the product, what was improved

      #### Phase Results Table
      | Phase | Findings | Accepted | Rejected | Applied | Notes |
      |-------|----------|----------|----------|---------|-------|
      For each of the 11 hardening steps, report counts and key metrics.

      #### Key Metrics
      - Total lint violations fixed
      - Dead code items removed
      - Dependencies updated / vulnerabilities patched
      - Security issues resolved
      - Duplications extracted
      - Error handling issues fixed
      - Type annotations added
      - Test inconsistencies fixed
      - Infrastructure issues fixed
      - E2E tests fixed / added
      - Test coverage before → after

      #### Remaining Items
      - Findings that were rejected with reasons
      - Issues flagged for manual review
      - Major dependency updates deferred

      ### 3. Do NOT
      - Re-do any work from prior phases
      - Make code changes — this is a reporting-only task
      - Editorialize about code quality — report facts

      ## Output
      Write the summary as a markdown file in the workspace root: `HARDENING_REPORT.md`
      """
    },

    # ===========================================================
    # Feature Implementation skills
    # ===========================================================

    # ── Phase 1: Analyze (parallel) ──

    %{
      "name" => "feature-kb-context",
      "description" =>
        "Retrieve relevant product knowledge from the Knowledge Base to inform feature implementation.",
      "category" => "feature-implementation",
      "tags" => "feature,kb,context,analysis",
      "built_in" => true,
      "content" => """
      # KB Context Retrieval

      ## Goal
      Pull all relevant product knowledge from the Knowledge Base so the planning and implementation
      agents start informed — not cold-reading the codebase.

      ## Process

      ### 1. Read the feature description
      From the issue title and description, identify:
      - The domain/area being changed (e.g. "tenant ETL", "auth", "billing")
      - Key entities, fields, or flows mentioned
      - Any explicit constraints or requirements

      ### 2. Search the Knowledge Base
      Look up KB notes for the selected product. Retrieve:
      - **Architecture**: System boundaries, service topology, data flow diagrams
      - **Business Logic**: Domain rules, invariants, validation logic relevant to the feature area
      - **Constraints**: Rate limits, security boundaries, data contracts that may affect the feature
      - **Workflows**: Existing process flows that the feature will interact with or modify
      - **Product Overview**: Feature inventory to understand what already exists

      ### 3. Summarize for downstream agents
      Write a structured context document that downstream agents can reference:

      ```markdown
      # KB Context: [Feature Area]

      ## Relevant Architecture
      [System boundaries, services, data stores involved]

      ## Business Rules & Invariants
      [Domain rules that MUST be preserved]

      ## Constraints
      [Technical limits, security boundaries, data contracts]

      ## Existing Workflows
      [Flows the feature touches or extends]

      ## Related Features
      [What already exists in this area]
      ```

      ## Output
      Write `KB_CONTEXT.md` to the workspace root.

      ## Rules
      - Do NOT make any code changes
      - Do NOT invent information — only report what the KB contains
      - If the KB has no relevant entries, say so explicitly
      """
    },
    %{
      "name" => "feature-impact-analysis",
      "description" =>
        "Analyze the codebase to identify files, modules, and functions affected by a feature change.",
      "category" => "feature-implementation",
      "tags" => "feature,impact,analysis,codebase",
      "built_in" => true,
      "content" => """
      # Codebase Impact Analysis

      ## Goal
      Identify every file, module, and function that will need to change for the feature.
      Produce a structured impact map so the planning agent knows the full scope.

      ## Process

      ### 1. Parse the feature description
      Extract the concrete changes requested: new fields, new endpoints, modified flows, etc.

      ### 2. Trace through the codebase
      For each change, trace the full path:
      - **Data layer**: schemas, migrations, types, database models
      - **Business layer**: service modules, domain logic, validation
      - **API layer**: endpoints, controllers, serializers, GraphQL resolvers
      - **UI layer**: components, pages, forms (if applicable)
      - **Test layer**: existing tests that cover the affected code
      - **Config layer**: environment variables, feature flags, config files

      ### 3. Identify risk areas
      Flag any changes that:
      - Touch shared/core modules used by other features
      - Modify database schemas (migration required)
      - Change public API contracts
      - Affect security-sensitive code (auth, permissions, data access)
      - Could break existing tests

      ## Output
      Write `IMPACT_ANALYSIS.md` to the workspace root:
      ```markdown
      # Impact Analysis: [Feature Title]

      ## Files to Modify
      | File | Change Type | Risk | Notes |
      |------|------------|------|-------|

      ## New Files to Create
      | File | Purpose |
      |------|---------|

      ## Migrations Required
      [Yes/No, with details]

      ## Risk Areas
      - [Shared module X used by Y, Z]
      - [Public API change affecting clients]

      ## Test Impact
      - Tests that will need updating: [list]
      - New tests needed: [list]
      ```

      ## Rules
      - Do NOT make any code changes
      - Be thorough — missing an affected file costs more later
      - When in doubt, include it in the impact map
      """
    },
    %{
      "name" => "feature-constraint-check",
      "description" =>
        "Cross-reference a feature against known constraints, security boundaries, and data contracts.",
      "category" => "feature-implementation",
      "tags" => "feature,constraints,validation,security",
      "built_in" => true,
      "content" => """
      # Constraint Check

      ## Goal
      Verify the feature does not violate known constraints, security policies, or data contracts.
      Flag conflicts BEFORE implementation begins.

      ## Process

      ### 1. Check against product constraints
      Review the KB context (from KB Context Retrieval) for:
      - Rate limits that the feature might exceed
      - Data retention policies affecting new fields
      - Size limits on payloads, records, or collections
      - Performance budgets (query time, response time)

      ### 2. Check security boundaries
      - Does the feature introduce new data that needs access control?
      - Are there PII/GDPR implications for new fields?
      - Does it modify authentication or authorization flows?
      - Are new external API calls needed (CORS, firewall rules)?

      ### 3. Check data contracts
      - Does the feature change API response shapes (breaking change)?
      - Are there downstream consumers that depend on the current schema?
      - Is backward compatibility required? For how long?
      - Are there message queue or event schemas affected?

      ### 4. Check infrastructure constraints
      - Database: will the migration lock tables? Estimated row count?
      - Deployment: feature flag needed? Rolling deploy safe?
      - Monitoring: new metrics, alerts, or dashboards needed?

      ## Output
      Write `CONSTRAINT_CHECK.md` to the workspace root:
      ```markdown
      # Constraint Check: [Feature Title]

      ## Status: [CLEAR / CONFLICTS FOUND]

      ## Conflicts
      | Constraint | Conflict | Severity | Mitigation |
      |-----------|----------|----------|------------|

      ## Warnings
      [Non-blocking concerns to address during implementation]

      ## Cleared Constraints
      [Constraints checked and passed]
      ```

      ## Rules
      - Do NOT make any code changes
      - CLEAR status means zero conflicts, not "probably fine"
      - Warnings are not blockers but should inform the plan
      """
    },

    # ── Phase 2: Plan ──

    %{
      "name" => "feature-implementation-plan",
      "description" =>
        "Generate a concrete implementation plan from analysis outputs: file changes, order, test strategy.",
      "category" => "feature-implementation",
      "tags" => "feature,plan,implementation,design",
      "built_in" => true,
      "content" => """
      # Implementation Plan

      ## Goal
      Produce a step-by-step implementation plan that a coding agent can follow mechanically.
      Read ALL predecessor outputs (KB Context, Impact Analysis, Constraint Check) before planning.

      ## Process

      ### 1. Synthesize predecessor outputs
      Read from the workspace:
      - `KB_CONTEXT.md` — relevant architecture, business rules, constraints
      - `IMPACT_ANALYSIS.md` — files to change, risks, test impact
      - `CONSTRAINT_CHECK.md` — conflicts, warnings, mitigations

      ### 2. Design the implementation
      Break the feature into ordered implementation steps:

      ```markdown
      ## Implementation Steps

      ### Step 1: [Database/Schema Changes]
      - Files: [list]
      - What: [specific changes]
      - Verification: [how to verify this step]

      ### Step 2: [Business Logic]
      - Files: [list]
      - What: [specific changes]
      - Verification: [how to verify this step]

      ### Step N: ...
      ```

      ### 3. Define the test strategy
      - Which existing tests need updating?
      - What new tests are needed?
      - Integration test considerations
      - Edge cases to cover

      ### 4. Define the rollback plan
      - What to revert if things go wrong
      - Feature flag recommendation (yes/no)

      ## Output
      Write `IMPLEMENTATION_PLAN.md` to the workspace root with:
      - Ordered implementation steps with file-level specificity
      - Test strategy
      - Rollback plan
      - Estimated scope (S/M/L) based on file count and risk

      ## Rules
      - Do NOT make any code changes
      - Steps must be specific enough that a coding agent can follow them without guessing
      - If a constraint conflict was found, the plan MUST address it
      - Prefer incremental steps that can each be verified independently
      """
    },

    # ── Phase 3: Implement ──

    %{
      "name" => "feature-code-implementation",
      "description" =>
        "Implement the feature by following the approved implementation plan. Write code, run tests.",
      "category" => "feature-implementation",
      "tags" => "feature,code,implementation,build",
      "built_in" => true,
      "content" => """
      # Code Implementation

      ## Goal
      Implement the feature by following the approved plan step by step. Write clean, tested code.

      ## Process

      ### 1. Read the approved plan
      Read `IMPLEMENTATION_PLAN.md` from the workspace. Follow it step by step.

      ### 2. Implement each step
      For each step in the plan:
      1. Make the changes described
      2. Run the verification command specified in the step
      3. Fix any issues before moving to the next step
      4. Commit after each logical unit (if using git)

      ### 3. Write/update tests
      Follow the test strategy from the plan:
      - Update existing tests broken by the changes
      - Write new tests for the new behavior
      - Ensure edge cases from the plan are covered

      ### 4. Final verification
      - Run the full test suite
      - Run linters/formatters
      - Verify no regressions

      ## Rules
      - Before running any commands, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - Follow the plan — do NOT deviate without good reason
      - If you discover the plan is wrong or incomplete, note it but implement what you can
      - Verify incrementally — do NOT batch all changes and test at the end
      - Do NOT change code outside the scope of the plan
      - Do NOT skip tests — if something is missing, install it
      """
    },

    # ── Phase 4: Verify & Document (parallel) ──

    %{
      "name" => "feature-test-verification",
      "description" =>
        "Write missing tests, update broken tests, and run the full test suite to verify the feature.",
      "category" => "feature-implementation",
      "tags" => "feature,test,verification,quality",
      "built_in" => true,
      "content" => """
      # Test Verification

      ## Goal
      Ensure the feature is fully tested. Write any missing tests, fix any broken tests,
      and produce a test coverage report.

      ## Process

      ### 1. Run existing tests
      Run the full test suite and capture results. Identify:
      - Tests that now fail due to the feature changes
      - Tests that pass but need updating (testing old behavior)

      ### 2. Fix broken tests
      Update tests to reflect the new behavior. Do NOT delete tests — update them.

      ### 3. Write new tests
      Based on the implementation plan's test strategy:
      - Unit tests for new functions/modules
      - Integration tests for new flows
      - Edge case tests identified in the plan
      - Regression tests for risk areas

      ### 4. Final suite run
      Run the complete test suite and report:
      - Total tests: pass/fail/skip
      - New tests added
      - Tests modified
      - Coverage delta (if measurable)

      ## Output
      Write `TEST_REPORT.md` to the workspace root:
      ```markdown
      # Test Report: [Feature Title]

      ## Suite Results
      - Total: X tests, Y passed, Z failed, W skipped

      ## New Tests Added
      | Test File | Test Name | What it covers |
      |-----------|-----------|----------------|

      ## Modified Tests
      | Test File | Test Name | Why modified |
      |-----------|-----------|--------------|

      ## Coverage
      [Before/after if measurable]
      ```

      ## Rules
      - Before running tests, install project dependencies first (npm install, pip install -r requirements.txt, mix deps.get, etc.)
      - ALL tests must pass before marking complete
      - Do NOT skip flaky tests — fix them
      - Do NOT skip because a tool is missing — install it
      - Do NOT change production code — only test code
      """
    },
    %{
      "name" => "feature-docs-changelog",
      "description" =>
        "Update documentation and changelog for the implemented feature.",
      "category" => "feature-implementation",
      "tags" => "feature,docs,changelog,documentation",
      "built_in" => true,
      "content" => """
      # Documentation & Changelog

      ## Goal
      Update all documentation affected by the feature and add a changelog entry.

      ## IMPORTANT — Where to make changes
      All documentation changes MUST be made in the **project's source repository**
      (the git repo where the production code lives), NOT in the `/workspace` scratch
      directory. The `/workspace` directory is only for reports and temporary files.

      - README.md → update the one in the **project repo root**, not /workspace/README.md
      - CHANGELOG.md → update or create in the **project repo root**
      - Inline docs → update in the **project repo source files**

      If the issue has a project_id, the project path is available. Work in that directory.

      ## Process

      ### 1. Update inline documentation
      - Add/update module-level docs for new or changed modules
      - Update function docs for changed public APIs
      - Add type specs for new functions (where the language supports it)

      ### 2. Update project documentation (in the project repo, NOT /workspace)
      - README changes (if user-facing behavior changed)
      - API documentation (new endpoints, changed responses)
      - Configuration documentation (new env vars, flags)

      ### 3. Write changelog entry (in the project repo, NOT /workspace)
      Add an entry to CHANGELOG.md (or equivalent):
      ```markdown
      ## [Unreleased]
      ### Added
      - [Feature description]

      ### Changed
      - [What existing behavior changed]
      ```

      ### 4. Write report to /workspace
      After making all changes in the project repo, write a summary report to
      `/workspace/reports/DOCS_CHANGELOG.md` listing what was updated and where.

      ### 5. Update KB context
      If the feature significantly changes architecture, business logic, or constraints,
      note what the KB extraction pipeline should re-extract.

      ## Rules
      - Do NOT change production code — documentation only
      - All doc changes go in the PROJECT REPO, reports go in /workspace/reports/
      - Match the existing documentation style
      - Changelog entries should be user-facing, not implementation details
      """
    }
  ]

  @default_groups [
    %{
      "name" => "Quality Essentials",
      "description" => "Core skills for ensuring agent work meets quality standards",
      "skill_names" => ["verification", "code-review"]
    },
    %{
      "name" => "Full Discipline",
      "description" => "Complete set of engineering discipline skills",
      "skill_names" => [
        "verification",
        "systematic-debugging",
        "test-driven-development",
        "plan-and-execute",
        "code-review"
      ]
    },
    %{
      "name" => "Research & Analysis",
      "description" => "Skills for investigation, evidence gathering, and written deliverables",
      "skill_names" => [
        "evidence-based-work",
        "structured-reporting",
        "scope-discipline"
      ]
    },
    %{
      "name" => "UI & Design",
      "description" => "Skills for user-facing interface design and layout consistency",
      "skill_names" => [
        "information-design",
        "ui-design"
      ]
    },
    %{
      "name" => "Documentation",
      "description" => "Skills for producing clear, audience-appropriate documentation",
      "skill_names" => [
        "structured-reporting",
        "information-design"
      ]
    },
    %{
      "name" => "Knowledge Extraction",
      "description" =>
        "Skills for extracting and documenting knowledge from codebases into structured KB notes",
      "skill_names" => [
        "extract-architecture",
        "extract-business-logic",
        "extract-constraints",
        "extract-workflows",
        "extract-product-overview"
      ]
    },
    %{
      "name" => "Product Hardening",
      "description" =>
        "Skills for the Product Health & Hardening pipeline — scan/apply pairs for lint, security," <>
          " DRY, coverage, and more",
      "skill_names" => [
        "hardening-lint-format-scan", "hardening-lint-format-apply",
        "hardening-dead-code-scan", "hardening-dead-code-apply",
        "hardening-dependency-audit-scan", "hardening-dependency-audit-apply",
        "hardening-security-scan-scan", "hardening-security-scan-apply",
        "hardening-dry-analysis-scan", "hardening-dry-analysis-apply",
        "hardening-error-handling-scan", "hardening-error-handling-apply",
        "hardening-type-safety-scan", "hardening-type-safety-apply",
        "hardening-test-style-scan", "hardening-test-style-apply",
        "hardening-infrastructure-scan", "hardening-infrastructure-apply",
        "hardening-playwright-e2e-scan", "hardening-playwright-e2e-apply",
        "hardening-test-coverage-scan", "hardening-test-coverage-apply",
        "hardening-pipeline-summary"
      ]
    },
    %{
      "name" => "Feature Implementation",
      "description" =>
        "Skills for the Feature Implementation pipeline — analyze, plan, implement, verify, document",
      "skill_names" => [
        "feature-kb-context",
        "feature-impact-analysis",
        "feature-constraint-check",
        "feature-implementation-plan",
        "feature-code-implementation",
        "feature-test-verification",
        "feature-docs-changelog"
      ]
    }
  ]

  @doc """
  Seed built-in skills if they don't already exist.
  Call this after LocalBoard is started.
  """
  def seed do
    existing = SymphonyElixir.LocalBoard.list_skills()
    existing_names = MapSet.new(existing, & &1.name)

    # Seed skills
    created_skills =
      Enum.reduce(@built_in_skills, %{}, fn skill_attrs, acc ->
        if MapSet.member?(existing_names, skill_attrs["name"]) do
          # Find existing skill by name to get its ID
          existing_skill = Enum.find(existing, &(&1.name == skill_attrs["name"]))
          Map.put(acc, skill_attrs["name"], existing_skill.id)
        else
          case SymphonyElixir.LocalBoard.create_skill(skill_attrs) do
            {:ok, skill} ->
              Logger.info("Seeded built-in skill: #{skill.name}")
              Map.put(acc, skill.name, skill.id)

            _ ->
              acc
          end
        end
      end)

    # Seed groups
    existing_groups = SymphonyElixir.LocalBoard.list_skill_groups()
    existing_group_names = MapSet.new(existing_groups, & &1.name)

    Enum.each(@default_groups, fn group_attrs ->
      unless MapSet.member?(existing_group_names, group_attrs["name"]) do
        # Resolve skill names to IDs
        skill_ids =
          Enum.flat_map(group_attrs["skill_names"], fn name ->
            case Map.get(created_skills, name) do
              nil -> []
              id -> [id]
            end
          end)

        attrs = %{
          "name" => group_attrs["name"],
          "description" => group_attrs["description"],
          "skill_ids" => skill_ids
        }

        case SymphonyElixir.LocalBoard.create_skill_group(attrs) do
          {:ok, group} ->
            Logger.info("Seeded skill group: #{group.name} with #{length(skill_ids)} skills")

          _ ->
            :ok
        end
      end
    end)

    :ok
  rescue
    e ->
      Logger.warning("Skills seed failed: #{Exception.message(e)}")
      :ok
  end
end
