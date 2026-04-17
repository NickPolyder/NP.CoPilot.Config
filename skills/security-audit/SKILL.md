---
name: security-audit
description: >
  Performs a systematic security assessment of a feature or codebase area using
  STRIDE threat modeling and OWASP Top 10 checklist. Produces a structured
  security report with findings, risk ratings, and remediation recommendations.
tags:
  - security
  - audit
  - threat-modeling
  - owasp
  - workflow
visibility: user
tools:
  [agent, code-review, edit/createFile, edit/editFiles, todo]
---

# Purpose

You are conducting a systematic security assessment.

Your goals are to:

- **Identify security risks** using structured threat modeling (STRIDE).
- **Check against known vulnerability categories** (OWASP Top 10).
- **Rate findings** by severity and exploitability.
- **Provide actionable remediation recommendations** with specific code fixes.
- **Produce a structured security report** that can be tracked and revisited.

---

# When to use this skill

Use this skill whenever:

- A new feature is being designed or implemented that handles sensitive data or authentication.
- The user asks for a security review, audit, or assessment.
- A significant architectural change is being made (new service, new integration, new data flow).
- A regular periodic security review is due.
- A security incident has occurred and the codebase needs review.

Do **not** use this skill for:

- Simple code reviews (use the `code-reviewer` agent instead).
- Pre-commit reviews (use the `git-commit-review` skill instead).
- Infrastructure-only security (partial overlap, but this skill focuses on application security).

---

# Audit process

## Step 1: Define scope

Establish the boundaries of the audit:

1. **Target**: What is being audited? (feature, service, endpoint, module, or full application)
2. **Assets**: What valuable data or functionality does it protect?
3. **Users**: Who interacts with this system? (end users, admins, services, external systems)
4. **Trust boundaries**: Where does trusted code meet untrusted input?

Document the scope before proceeding:

```markdown
## Audit Scope

- **Target**: {feature/service name}
- **Codebase**: {repository, paths}
- **Assets**: {data and functionality to protect}
- **Users**: {who interacts with this system}
- **Trust boundaries**: {where trusted meets untrusted}
- **Out of scope**: {explicitly excluded areas}
```

## Step 2: Map data flows

Trace how data moves through the system:

1. Identify all **entry points** (API endpoints, UI forms, message consumers, file uploads).
2. Trace data through **processing layers** (controllers, services, domain, infrastructure).
3. Identify **storage locations** (databases, caches, files, external services).
4. Identify **exit points** (API responses, UI rendering, logs, external API calls, emails).

Create a data flow summary:

```
Entry Point → Processing → Storage → Exit Point
   ↓              ↓           ↓          ↓
{source}     {validation?}  {encrypted?} {encoded?}
{authn?}     {authz?}       {access?}    {filtered?}
```

## Step 3: Apply STRIDE threat modeling

For each component and data flow, evaluate threats:

| Threat | Question to Ask | What to Look For |
|---|---|---|
| **Spoofing** | Can someone pretend to be another user/service? | Missing authentication, weak token validation, no MFA |
| **Tampering** | Can data be modified in transit or at rest? | No integrity checks, missing HTTPS, SQL injection, mass assignment |
| **Repudiation** | Can a user deny performing an action? | Missing audit logs, no event tracking, unsigned transactions |
| **Information Disclosure** | Can unauthorized parties see sensitive data? | Verbose errors, log leaks, missing encryption, over-fetching |
| **Denial of Service** | Can the system be made unavailable? | No rate limiting, unbounded queries, resource exhaustion |
| **Elevation of Privilege** | Can someone gain unauthorized access? | Broken access control, IDOR, missing authz checks, role confusion |

Rate each threat:

| Likelihood | Impact | Risk Level |
|---|---|---|
| High | High | 🔴 CRITICAL |
| High | Medium | 🟠 HIGH |
| Medium | High | 🟠 HIGH |
| Medium | Medium | 🟡 MEDIUM |
| Low | High | 🟡 MEDIUM |
| Low | Medium | 🟢 LOW |
| Low | Low | 🟢 LOW |

## Step 4: OWASP Top 10 checklist

Systematically check each category:

### A01: Broken Access Control
- [ ] Authorization checked on every API endpoint (server-side)
- [ ] No IDOR vulnerabilities (users can't access other users' data)
- [ ] CORS configured with specific origins (no wildcards in production)
- [ ] Directory listing disabled
- [ ] Rate limiting on sensitive endpoints
- [ ] JWT/token validation checks signature, expiration, audience, issuer

### A02: Cryptographic Failures
- [ ] TLS 1.2+ enforced for all communication
- [ ] Sensitive data encrypted at rest (database, files)
- [ ] Passwords hashed with bcrypt/Argon2/PBKDF2 (high iterations)
- [ ] No sensitive data in URLs or query strings
- [ ] Cryptographic keys rotated on schedule
- [ ] No deprecated algorithms (MD5, SHA1, DES)

### A03: Injection
- [ ] All database queries parameterized (no string concatenation)
- [ ] User input validated on server side (type, length, format, range)
- [ ] Output encoded based on context (HTML, JS, URL, CSS)
- [ ] Content Security Policy (CSP) headers configured
- [ ] No eval() or dynamic code execution with user input
- [ ] File uploads validated (type, size, content inspection)

### A04: Insecure Design
- [ ] Threat model exists for the feature/system
- [ ] Abuse cases considered alongside use cases
- [ ] Rate limiting and resource quotas in place
- [ ] Principle of least privilege applied
- [ ] Fail-secure defaults (deny by default)

### A05: Security Misconfiguration
- [ ] Debug/development features disabled in production
- [ ] Security headers set (HSTS, X-Content-Type-Options, X-Frame-Options, CSP)
- [ ] Default credentials removed/changed
- [ ] Error pages don't expose stack traces or internal details
- [ ] Unnecessary features and endpoints disabled
- [ ] Dependencies up to date (no known CVEs)

### A06: Vulnerable Components
- [ ] Dependency scanning enabled (Dependabot, Snyk)
- [ ] No known CVEs in current dependencies
- [ ] Minimal dependencies (each is justified)
- [ ] Dependencies from trusted sources only
- [ ] Lock files committed (package-lock.json, etc.)

### A07: Authentication Failures
- [ ] Strong password policy (length > 12, not just complexity)
- [ ] Account lockout/throttling for brute force protection
- [ ] MFA available for sensitive operations
- [ ] Session management secure (HttpOnly, Secure, SameSite cookies)
- [ ] Password reset flow is secure (time-limited tokens, no info leakage)
- [ ] OAuth 2.0/OIDC implemented correctly (PKCE for public clients)

### A08: Data Integrity Failures
- [ ] CI/CD pipeline secured (signed commits, protected branches)
- [ ] Software updates verified (signed packages)
- [ ] Deserialization uses safe methods (no arbitrary type instantiation)
- [ ] Data from untrusted sources validated before use

### A09: Logging & Monitoring Failures
- [ ] Security events logged (login, failed auth, privilege changes)
- [ ] Sensitive data NOT logged (passwords, tokens, PII)
- [ ] Logs are tamper-evident
- [ ] Alerting configured for suspicious patterns
- [ ] Log retention meets compliance requirements

### A10: Server-Side Request Forgery (SSRF)
- [ ] URLs validated before server-side requests
- [ ] Allowlist for permitted domains/IPs
- [ ] Unnecessary URL schemes disabled (file://, gopher://)
- [ ] Network segmentation limits SSRF blast radius

## Step 5: Present findings for approval

Before proceeding to code review, present the threat analysis findings to the user:

> **Threat analysis complete (STRIDE + OWASP). Found: {critical} critical, {high} high, {medium} medium, {low} low severity issues. Code review follows next.**
>
> **Top findings:**
> 1. {Most critical finding — one line}
> 2. {Second most critical — one line}
> 3. {Third — one line}
>
> **Proceed with code review and full report generation? (yes / no / adjust scope)**

This gate ensures the user sees the severity landscape before investing time in detailed remediation guidance.

---

## Step 6: Code review for security

Examine the actual code for security issues:

1. **Authentication code** — token validation, session management, MFA logic.
2. **Authorization code** — policy definitions, resource-based checks, role assignments.
3. **Input handling** — validation, sanitization, deserialization.
4. **Data access** — query construction, connection string handling, stored procedures.
5. **Cryptography** — key management, algorithm choices, random number generation.
6. **Error handling** — exception details, error messages, fallback behavior.
7. **Logging** — what's logged, what's not, log injection prevention.
8. **Configuration** — secrets handling, feature flags, environment separation.

## Step 7: Generate the report

Produce a structured security assessment report:

```markdown
# Security Assessment: {Feature/System}

**Date:** {date}
**Scope:** {what was audited}
**Auditor:** security-engineer agent

## Executive Summary

{2-3 sentence overview: overall risk level, critical findings count, key recommendations}

## Threat Model

| # | Component | Threat (STRIDE) | Risk | Mitigation | Status |
|---|---|---|---|---|---|
| T1 | {component} | {threat} | 🔴/🟠/🟡/🟢 | {mitigation} | ✅/⚠️/❌ |

## OWASP Top 10 Assessment

| Category | Status | Notes |
|---|---|---|
| A01: Broken Access Control | ✅/⚠️/❌ | {notes} |
| A02: Cryptographic Failures | ✅/⚠️/❌ | {notes} |
| ... | ... | ... |

## Findings

### 🔴 CRITICAL
- **{file:line}** — {description}
  - **Risk:** {what could happen}
  - **Fix:** {specific remediation with code example}

### 🟠 HIGH
- **{file:line}** — {description}
  - **Risk:** {what could happen}
  - **Fix:** {specific remediation}

### 🟡 MEDIUM
- **{file:line}** — {description}
  - **Fix:** {recommendation}

### 🟢 LOW
- **{file:line}** — {description}
  - **Fix:** {suggestion}

## Remediation Priority

| Priority | Finding | Effort | Impact |
|---|---|---|---|
| 1 | {finding} | Low/Med/High | 🔴 CRITICAL |
| 2 | {finding} | Low/Med/High | 🟠 HIGH |

## Compliance Notes
- {GDPR, SOC2, or other relevant compliance considerations}

## Recommendations
1. {Immediate action items}
2. {Short-term improvements}
3. {Long-term security enhancements}
```

---

# Report storage

After completing the audit, persist the report:

1. **Path**: `.copilot/reports/security/{yyyy}/{MM}/security-audit-{dd}-{hhmmss}.md`
2. **Create directories** as needed.
3. **`.gitignore` reminder**: Ensure `/.copilot/` is listed in `.gitignore`.

---

# Agent coordination

During the audit, involve specialist agents as needed:

| Situation | Agent to Consult |
|---|---|
| Architecture-level threats | `architect` |
| Backend code review | `backend-developer` |
| Frontend security (XSS, CSP) | `frontend-developer` |
| Database access patterns | `database-engineer` |
| Service integration security | `systems-engineer` |
| Infrastructure security | `devops-engineer` |
| Service Fabric security | `service-fabric-engineer` |
| Auth UX flows | `ux-engineer` |
| Test coverage for security | `qa-engineer` |

---

# Example output

## Input

> "Please do a security audit of our user authentication module."

## Output (abbreviated)

```markdown
# Security Assessment: User Authentication Module

**Date:** 2026-04-13
**Scope:** src/Auth/ — login, registration, password reset, token management
**Auditor:** security-engineer agent

## Executive Summary

The authentication module has **1 critical** and **2 high** severity findings.
The critical finding is an insecure password reset flow that allows account takeover.
Overall, the module follows good practices but needs immediate attention on the
password reset endpoint and token storage.

## Threat Model

| # | Component | Threat | Risk | Mitigation | Status |
|---|---|---|---|---|---|
| T1 | Login endpoint | Spoofing (brute force) | 🟠 HIGH | Rate limiting | ⚠️ Partial (no progressive delay) |
| T2 | Password reset | Tampering (token reuse) | 🔴 CRITICAL | One-time tokens | ❌ Missing |
| T3 | JWT tokens | Info Disclosure | 🟡 MEDIUM | Short expiry | ✅ Implemented |
| T4 | Login page | DoS (flood) | 🟡 MEDIUM | Rate limiting | ⚠️ Per-IP only |

## Findings

### 🔴 CRITICAL
- **src/Auth/PasswordResetService.cs:47** — Password reset tokens are not invalidated after use.
  - **Risk:** Attacker who intercepts a reset email can use the token repeatedly.
  - **Fix:** Mark token as used in database after successful reset:
    ```csharp
    await _tokenStore.InvalidateAsync(token, cancellationToken);
    ```

### 🟠 HIGH
- **src/Auth/LoginController.cs:23** — No progressive delay on failed login attempts.
  - **Risk:** Brute force attacks are feasible despite rate limiting.
  - **Fix:** Implement exponential backoff after 3 failed attempts.
```

---

# Checklist

1. ☐ Scope clearly defined (target, assets, users, trust boundaries)
2. ☐ Data flows mapped (entry → processing → storage → exit)
3. ☐ STRIDE applied to all components and data flows
4. ☐ All 10 OWASP categories checked
5. ☐ Code reviewed for security-specific patterns
6. ☐ Findings rated by severity (CRITICAL/HIGH/MEDIUM/LOW)
7. ☐ Remediation recommendations are specific and actionable
8. ☐ Report generated and stored
9. ☐ Critical findings flagged for immediate attention

---

# Rules

- Always define scope before starting the audit — never audit "everything" without boundaries.
- Rate findings honestly — don't inflate severity to seem thorough.
- Provide specific remediation with code examples, not just "fix this."
- If you can't fully assess a finding, note the uncertainty and recommend further investigation.
- Never expose actual secrets, credentials, or sensitive data in the report.
- Critical findings must be communicated immediately — don't wait for the full report.
- Follow existing security patterns in the codebase when recommending fixes.
