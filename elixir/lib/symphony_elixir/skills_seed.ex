defmodule SymphonyElixir.SkillsSeed do
  @moduledoc """
  Seeds built-in skills into the LocalBoard on first startup.

  These skills are inspired by the Superpowers project and adapted
  for Symphony's autonomous agent orchestration context.
  """

  require Logger

  @built_in_skills [
    %{
      "name" => "verification-before-completion",
      "description" =>
        "Use when the agent is about to claim a task is done. Ensures completion claims are backed by evidence.",
      "category" => "quality",
      "tags" => "gate,completion,verification",
      "built_in" => true,
      "content" => """
      # Verification Before Completion

      ## Iron Law
      **No completion claims without fresh verification evidence.**

      You MUST NOT claim that work is "done", "complete", "passing", or "working" unless you have:
      1. Run the actual verification command (test, build, lint) in the current turn
      2. Read and shown the output
      3. Confirmed the output demonstrates success

      ## What counts as verification
      - Running `mix test` and seeing "0 failures"
      - Running the build command and seeing it exit 0
      - Running the linter and seeing no errors
      - Executing the code path and observing correct output

      ## What does NOT count
      - "I believe the tests pass" (without running them)
      - "This should work" (without executing)
      - "Based on my changes, everything should be fine"
      - Referencing test output from a previous turn

      ## Rationalization Prevention
      | Excuse | Rebuttal |
      |--------|----------|
      | "The change is trivial" | Trivial changes cause production outages. Verify. |
      | "I already verified earlier" | State may have changed. Verify again. |
      | "Tests take too long" | Run the relevant subset. Never skip entirely. |
      | "The build system isn't available" | Then you cannot claim completion. Report the blocker. |
      """
    },
    %{
      "name" => "systematic-debugging",
      "description" =>
        "Use when investigating a bug, test failure, or unexpected behavior. Enforces root cause investigation before fixes.",
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
      "name" => "design-before-code",
      "description" =>
        "Use when starting a new feature or significant change. Ensures design thinking before implementation.",
      "category" => "planning",
      "tags" => "design,planning,architecture",
      "built_in" => true,
      "content" => """
      # Design Before Code

      ## Iron Law
      **No code without a design outline first.**

      ## Process

      ### 1. Clarify Requirements
      - What exactly is being asked for?
      - What are the acceptance criteria?
      - What edge cases exist?
      - What constraints apply (performance, compatibility, etc.)?

      ### 2. Explore the Existing Code
      - Read the relevant modules before proposing changes
      - Understand the existing patterns and conventions
      - Identify what can be reused vs. what needs to be built

      ### 3. Outline the Approach
      Before writing any implementation code, document:
      - Which files will be modified or created
      - What the key data structures will look like
      - How the components will interact
      - What tests will verify the behavior

      ### 4. Consider Alternatives
      - Is there a simpler way to achieve this?
      - What are the trade-offs of this approach?
      - Will this be maintainable?

      ### 5. Then Implement
      Only after steps 1-4 are complete, begin writing code.
      Follow the plan. If you discover the plan needs to change,
      update the plan first, then change the code.
      """
    },
    %{
      "name" => "executing-plans",
      "description" =>
        "Use when following a multi-step implementation plan. Ensures step-by-step execution with checkpoints.",
      "category" => "workflow",
      "tags" => "execution,plan,checkpoints",
      "built_in" => true,
      "content" => """
      # Executing Plans

      ## Process

      ### Step-by-Step Execution
      - Work through the plan one step at a time
      - Complete each step fully before moving to the next
      - Run tests/verification after each step
      - Do not skip ahead or combine steps

      ### Checkpoint After Each Step
      After completing each step, verify:
      1. The step's specific tests pass
      2. No existing tests were broken
      3. The code compiles without warnings

      ### Handling Blockers
      If a step cannot be completed as planned:
      - STOP — do not guess or improvise
      - Document what the blocker is
      - Explain what was attempted
      - Suggest how to unblock

      ### Do Not
      - Skip steps because they "seem unnecessary"
      - Combine multiple steps into one
      - Reorder steps without clear justification
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
      "name" => "source-verification",
      "description" =>
        "Use when gathering information from external sources. Ensures claims are backed by citations and multiple sources are cross-referenced.",
      "category" => "research",
      "tags" => "research,citations,sources,verification",
      "built_in" => true,
      "content" => """
      # Source Verification

      ## Iron Law
      **No claims without citations. No conclusions from a single source.**

      ## Requirements

      ### Every factual claim must have a source
      - Link to the original documentation, article, or code
      - If you cannot find a source, say "I could not verify this" — do not assert it as fact
      - Distinguish clearly between what a source says vs. your inference from it

      ### Cross-reference multiple sources
      - Do not rely on a single source for important claims
      - When sources conflict, report the conflict explicitly — do not silently pick one
      - Prefer primary sources (official docs, RFCs, source code) over secondary (blog posts, tutorials)

      ### Flag uncertainty
      - Use explicit confidence markers: "confirmed", "likely", "uncertain", "conflicting sources"
      - Never present speculation as established fact
      - If a topic lacks reliable sources, say so rather than filling the gap with guesses

      ## Anti-Patterns
      - "According to best practices..." (which best practices? whose? citation needed)
      - Presenting a single blog post as definitive
      - Mixing your opinion with sourced facts without clear separation
      """
    },
    %{
      "name" => "structured-reporting",
      "description" =>
        "Use when producing written deliverables. Enforces clear structure with summary, evidence, and actionable conclusions.",
      "category" => "research",
      "tags" => "research,writing,reports,structure",
      "built_in" => true,
      "content" => """
      # Structured Reporting

      ## Iron Law
      **Executive summary first. Evidence second. "So what?" last.**

      ## Required Structure

      ### 1. Summary (2-3 sentences max)
      - What was investigated
      - What was found
      - What should be done about it

      ### 2. Key Findings (bulleted, scannable)
      - Each finding is a standalone statement backed by evidence
      - Ordered by importance, not by discovery sequence
      - No finding without supporting evidence in the details section

      ### 3. Detailed Analysis
      - Organized by topic, not chronologically
      - Each section has a clear heading that communicates the conclusion
      - Evidence presented with sources (links, data, code references)

      ### 4. Recommendations (actionable)
      - Each recommendation is concrete and actionable
      - Includes effort estimate or complexity signal
      - Distinguishes "must do" from "should consider"

      ## Anti-Patterns
      - Stream-of-consciousness writing ("First I looked at X, then I tried Y...")
      - Burying the conclusion at the end
      - Recommendations without supporting evidence
      - Vague advice ("consider improving performance")
      """
    },
    %{
      "name" => "audience-aware-writing",
      "description" =>
        "Use when writing documentation or technical content. Ensures content is tailored to its intended audience and context.",
      "category" => "documentation",
      "tags" => "documentation,writing,audience,clarity",
      "built_in" => true,
      "content" => """
      # Audience-Aware Writing

      ## Iron Law
      **Identify who will read this before writing a single line.**

      ## Process

      ### 1. Identify the Reader
      Before writing, answer:
      - Who is the primary audience? (developer, operator, end-user, reviewer)
      - What do they already know? (don't explain what's obvious to them)
      - What are they trying to do? (task-oriented, not feature-oriented)

      ### 2. Match the Level
      - For developers: include code examples, API signatures, edge cases
      - For operators: include commands, config options, troubleshooting
      - For end-users: include step-by-step instructions, screenshots, expected outcomes
      - For reviewers: include rationale, trade-offs, alternatives considered

      ### 3. Structure for Scanning
      - Lead with what the reader needs most
      - Use headings that answer questions ("How to X" not "Section 3.2")
      - Include prerequisites upfront — never assume unstated context
      - Every code example must be complete enough to actually run or copy

      ### 4. Verify
      - Would someone with the stated background understand this without asking questions?
      - Are all terms either common knowledge for the audience or defined?
      - Is every example tested and working?

      ## Anti-Patterns
      - Writing for yourself instead of the reader
      - Assuming context that isn't stated
      - Code snippets that don't work when copied
      - "See also: [link]" as a substitute for explanation
      """
    },
    %{
      "name" => "incremental-verification",
      "description" =>
        "Use when making changes across multiple files or systems. Ensures each change is verified before moving to the next.",
      "category" => "workflow",
      "tags" => "verification,incremental,multi-file,safety",
      "built_in" => true,
      "content" => """
      # Incremental Verification

      ## Iron Law
      **Verify after every logical change. Never batch all changes then hope.**

      ## Process

      ### After each logical unit of change:
      1. Save and compile — confirm no syntax errors
      2. Run the most relevant test or check for that change
      3. If it fails, fix it NOW before moving on
      4. Only proceed to the next change after green

      ### What counts as a "logical unit"
      - One function added or modified
      - One file's changes completed
      - One integration point connected
      - One config change applied

      ### What does NOT count
      - "I'll test everything at the end" — this is the anti-pattern this skill exists to prevent
      - "These changes are all related so I'll verify them together" — verify each one
      - "It's just a rename" — renames break things. Verify.

      ## Escalation
      If verification reveals a problem:
      - Fix it before making any more changes
      - If the fix requires rethinking the approach, stop and reassess
      - Do not stack more changes on top of a broken foundation

      ## Rationalization Prevention
      | Excuse | Rebuttal |
      |--------|----------|
      | "Verifying each step is slow" | Debugging a pile of untested changes is slower. |
      | "These are trivial changes" | Then verifying them is trivial too. Do it. |
      | "I'll just do one more thing first" | That's how five unverified changes become ten. Stop. |
      """
    },
    %{
      "name" => "scope-discipline",
      "description" =>
        "Use when working on any task with defined boundaries. Prevents scope creep and keeps work focused on the stated objective.",
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
      - Add error handling for scenarios that aren't part of the task
      - "Improve" things you weren't asked to improve

      ### When you discover something out of scope
      - Note it as a potential follow-up issue
      - Do NOT fix it in the current task
      - If it blocks your current task, document the blocker — don't expand scope to fix it

      ### The test
      Every change in your diff should trace directly to a requirement in the issue.
      If you can't point to which requirement a change serves, remove it.

      ## Rationalization Prevention
      | Excuse | Rebuttal |
      |--------|----------|
      | "It's a small improvement" | Small improvements compound into large, unreviewable diffs. |
      | "I'm already in this file" | Being in a file is not a mandate to change it. |
      | "Future me will thank me" | Future you will thank present you for a focused, reviewable PR. |
      """
    },
    %{
      "name" => "evidence-based-decisions",
      "description" =>
        "Use when choosing between approaches or making technical recommendations. Requires concrete evidence before recommending a path.",
      "category" => "planning",
      "tags" => "decisions,evidence,trade-offs,analysis",
      "built_in" => true,
      "content" => """
      # Evidence-Based Decisions

      ## Iron Law
      **No recommendations without evidence. No evidence without data.**

      ## Process

      ### When recommending an approach:
      1. State at least two alternatives you considered
      2. For each alternative, provide concrete evidence (benchmarks, code examples, documentation)
      3. Identify the trade-offs explicitly — nothing is free
      4. State which trade-offs matter most for THIS context and why

      ### What counts as evidence
      - Benchmark results (with methodology described)
      - Code examples demonstrating the difference
      - Official documentation or specifications
      - Production data or metrics from comparable systems
      - Concrete examples of the approach working (or failing) elsewhere

      ### What does NOT count
      - "Best practice" (whose? in what context? citation needed)
      - "Industry standard" (which industry? which standard?)
      - "It's generally considered..." (by whom?)
      - Personal preference presented as technical necessity
      - Premature performance claims without measurement

      ## Anti-Patterns
      - Recommending the first approach that comes to mind without exploring alternatives
      - Using authority ("Google does it this way") instead of technical reasoning
      - Optimizing for the wrong dimension (performance when correctness is the concern)
      """
    },
    %{
      "name" => "content-hierarchy",
      "description" =>
        "Use when organizing information, navigation, or page structure. Ensures content is structured by user mental models, not system internals.",
      "category" => "information-architecture",
      "tags" => "ia,hierarchy,navigation,organization",
      "built_in" => true,
      "content" => """
      # Content Hierarchy

      ## Iron Law
      **Organize by what users look for, not by how the system stores it.**

      ## Principles

      ### Structure follows user intent
      - Group content by what users are trying to accomplish, not by database tables or API endpoints
      - Navigation labels should use the user's language, not internal jargon
      - The most common tasks should be the easiest to find — measure by clicks/taps to goal

      ### Progressive disclosure
      - Show summary first, details on demand
      - Each level of depth should serve a smaller, more specific audience
      - Never force all users through information only some users need

      ### Every piece of content has a "home"
      - If users would look for it in two places, it should be findable from both (but live in one)
      - Cross-references and shortcuts are fine; duplication is not
      - Orphaned content (reachable only by direct URL) is a bug

      ### Hierarchy signals meaning
      - Visual weight (size, color, position) must match actual importance
      - Primary actions are visually dominant; secondary actions are subdued
      - Related items are visually grouped; unrelated items are visually separated

      ## Anti-Patterns
      - Flat lists of 20+ items with no grouping
      - Navigation that mirrors the codebase folder structure
      - Hiding critical actions behind menus while decorative elements are prominent
      - Equal visual weight for everything (means nothing is important)
      """
    },
    %{
      "name" => "user-journey-first",
      "description" =>
        "Use when designing flows, modals, forms, or multi-step interactions. Ensures every UI decision is grounded in what the user is trying to accomplish.",
      "category" => "ux",
      "tags" => "ux,user-journey,flows,interactions",
      "built_in" => true,
      "content" => """
      # User Journey First

      ## Iron Law
      **State the user's goal before choosing any layout, component, or interaction.**

      ## Process

      ### 1. Articulate the goal
      Before designing any UI, write one sentence:
      "The user wants to [verb] [object] so that [outcome]."
      If you can't fill this in, you don't understand the requirement yet.

      ### 2. Map the happy path
      - What is the minimum number of steps to reach the goal?
      - Each step should have one clear action and one clear outcome
      - If a step doesn't move the user toward the goal, remove it

      ### 3. Handle the real paths
      - Empty states: what does the user see before any data exists?
      - Error states: what happens when something goes wrong? Can the user recover?
      - Loading states: what does the user see while waiting?
      - Edge cases: what if there are 0 items? 1,000 items? Very long text?

      ### 4. Reduce friction
      - Every click/tap/keystroke is a cost. Minimize them.
      - Prefer smart defaults over blank forms
      - Prefer inline editing over navigate-to-edit-page
      - Prefer progressive disclosure over front-loading all options

      ## Anti-Patterns
      - Designing the UI around available API fields instead of user goals
      - Adding a feature to the UI because the backend supports it, not because users need it
      - Ignoring empty/error/loading states (they ARE the user's first experience)
      - Requiring confirmation for low-risk, easily reversible actions
      """
    },
    %{
      "name" => "cognitive-load-budget",
      "description" =>
        "Use when designing interfaces or information displays. Ensures the user is never asked to hold more than they can process.",
      "category" => "ux",
      "tags" => "ux,cognitive-load,psychology,simplicity",
      "built_in" => true,
      "content" => """
      # Cognitive Load Budget

      ## Iron Law
      **If the user has to think about the interface instead of their task, the design failed.**

      ## Principles

      ### Chunk information (7±2 rule)
      - No more than 5-9 items in any ungrouped list, menu, or set of options
      - If you have more, group them into logical categories
      - Each group gets a descriptive label that aids scanning

      ### Defaults over decisions
      - Every form field should have a sensible default when possible
      - The most common choice should be pre-selected
      - Advanced options should be hidden until needed, not presented upfront

      ### Recognition over recall
      - Show available options rather than requiring the user to remember them
      - Use consistent patterns — the same action should look and work the same everywhere
      - Inline context (tooltips, descriptions) over "refer to documentation"

      ### Visual grouping reduces cognitive work
      - Related controls are physically close together
      - Unrelated controls are visually separated (whitespace, dividers, cards)
      - Alignment creates implicit relationships — misalignment creates confusion

      ### One primary action per view
      - Every screen/modal/panel should have ONE obvious thing to do next
      - Secondary actions are visually subdued
      - Destructive actions require deliberate effort (not one accidental click)

      ## Anti-Patterns
      - Showing all settings/options at once ("the cockpit problem")
      - Using jargon or internal terminology in user-facing labels
      - Requiring the user to cross-reference information across multiple views
      - Modal dialogs that contain more modals
      """
    },
    %{
      "name" => "spatial-consistency",
      "description" =>
        "Use when creating or modifying visual layouts, spacing, or component arrangements. Ensures a coherent spatial language across the interface.",
      "category" => "design",
      "tags" => "design,layout,spacing,consistency,css",
      "built_in" => true,
      "content" => """
      # Spatial Consistency

      ## Iron Law
      **No magic numbers. Every spacing, size, and position decision follows the system.**

      ## Rules

      ### Use the existing spacing scale
      - Identify the project's spacing tokens/variables (4px, 8px, 12px, 16px, 24px, etc.)
      - Never use arbitrary pixel values — always map to the nearest scale step
      - If no scale exists, establish one and use it consistently

      ### Consistent alignment
      - Elements that serve the same role align to the same grid
      - Left edges align. Baseline text aligns. Icon centers align.
      - If two things look like they should be aligned but aren't, that's a bug

      ### Predictable component placement
      - Navigation: always in the same position (typically left or top)
      - Primary actions: always in the same position (typically bottom-right of their container)
      - Destructive actions: visually separated from constructive actions
      - Consistent ordering: if lists have a sort order, it's the same everywhere

      ### Whitespace is intentional
      - Whitespace groups related items and separates unrelated ones
      - More space between groups, less space within groups
      - Consistent padding within component types (all cards have the same internal spacing)
      - Empty space is not wasted space — it's a design element

      ### Responsive behavior
      - Components reflow predictably at breakpoints
      - Nothing overflows, overlaps, or disappears unexpectedly
      - Touch targets are at least 44x44px on mobile

      ## Anti-Patterns
      - `margin-top: 13px` (why 13? use the scale)
      - Different padding on every card variant
      - Centering something vertically with a magic pixel offset
      - Layout that works at exactly one screen size
      """
    },
    %{
      "name" => "extract-architecture",
      "description" =>
        "Use when extracting system architecture from a codebase. Produces a structured KB note documenting components, boundaries, data flow, and tech stack.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,architecture,documentation,kb",
      "built_in" => true,
      "content" => """
      # Extract Architecture

      ## Goal
      Produce a structured KB note that documents the system's architecture so that anyone — human or agent — can understand the system's shape without reading every file.

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
        "Use when extracting business rules and domain logic from a codebase. Produces a structured KB note cataloging validation rules, state machines, invariants, and domain concepts.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,business-logic,domain,rules,kb",
      "built_in" => true,
      "content" => """
      # Extract Business Logic

      ## Goal
      Produce a structured KB note that catalogs the business rules embedded in the code — the "why" behind conditionals, validations, and state transitions.

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
        "Use when extracting technical constraints and limitations from a codebase. Produces a structured KB note documenting performance limits, security boundaries, compatibility requirements, and operational constraints.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,constraints,limits,security,kb",
      "built_in" => true,
      "content" => """
      # Extract Technical Constraints

      ## Goal
      Produce a structured KB note that documents the hard limits, boundaries, and non-negotiable requirements baked into the system — the things you cannot change without consequences.

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
        "Use when extracting process workflows from a codebase. Produces a structured KB note documenting how data and work flow through the system — pipelines, lifecycles, and multi-step processes.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,workflows,processes,lifecycle,kb",
      "built_in" => true,
      "content" => """
      # Extract Process Workflows

      ## Goal
      Produce a structured KB note that documents the end-to-end processes in the system — how things move from start to finish, who/what is involved at each step, and what triggers transitions.

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
        "Use when extracting a product or project overview from a codebase. Produces a structured KB note with feature inventory, completeness status, and project structure.",
      "category" => "knowledge-extraction",
      "tags" => "extraction,product,features,overview,kb",
      "built_in" => true,
      "content" => """
      # Extract Product/Project Overview

      ## Goal
      Produce a structured KB note that gives a complete picture of what the product does, what features exist, how complete they are, and how the project is organized.

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
    }
  ]

  @default_groups [
    %{
      "name" => "Quality Essentials",
      "description" => "Core skills for ensuring agent work meets quality standards",
      "skill_names" => ["verification-before-completion", "code-review"]
    },
    %{
      "name" => "Full Discipline",
      "description" => "Complete set of engineering discipline skills",
      "skill_names" => [
        "verification-before-completion",
        "systematic-debugging",
        "test-driven-development",
        "design-before-code",
        "executing-plans",
        "code-review"
      ]
    },
    %{
      "name" => "Research & Analysis",
      "description" => "Skills for investigation, evidence gathering, and written deliverables",
      "skill_names" => [
        "source-verification",
        "structured-reporting",
        "evidence-based-decisions",
        "scope-discipline"
      ]
    },
    %{
      "name" => "UI & Design",
      "description" => "Skills for user-facing interface design and layout consistency",
      "skill_names" => [
        "content-hierarchy",
        "user-journey-first",
        "cognitive-load-budget",
        "spatial-consistency"
      ]
    },
    %{
      "name" => "Documentation",
      "description" => "Skills for producing clear, audience-appropriate documentation",
      "skill_names" => [
        "audience-aware-writing",
        "structured-reporting",
        "content-hierarchy"
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
