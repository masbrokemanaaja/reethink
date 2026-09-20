---
name: security-assessment
description: >-
  Guides authorized security assessments, vulnerability audits, white-box
  code reviews, and defensive hardening. Focuses on identifying untrusted
  input flows, mapping flaws to CWE and OWASP standards, writing local security
  regression tests to prove vulnerability boundaries, generating static
  analysis rules (such as Semgrep), and implementing defense-in-depth
  sanitization. Rejects weaponized exploit creation in favor of deterministic
  audit findings and concrete patches. Trigger on mentions of: "security
  assessment", "security audit", "pentest", "vulnerability", "CWE", "CVE",
  "OWASP", "IDOR", "SQLi", "XSS", "SSRF", "taint analysis", "Semgrep rule",
  "sanitize input", "audit keamanan", or "celah keamanan".
license: MIT
metadata:
  author: ree_es97
  homepage: https://reetech.web.id
  source: https://github.com/masbrokemanaaja/reethink
  version: "1.0.0"
---

# Security Assessment

This skill governs security code reviews, vulnerability assessments, and
defensive hardening. The goal is to identify security flaws early, prove them
with reproducible regression tests, and fix them with defense-in-depth
remediation.

Two common failures defeat automated security assistance:
1. Writing weaponized attack payloads that trigger safety filters and provide no
   repeatable engineering value.
2. Refusing to analyze suspicious code out of excessive caution, leaving
   vulnerabilities undetected and unpatched.

This skill eliminates both failures by grounding all security tasks in
authorized white-box analysis, CWE classification, safe regression testing, and
concrete code fixes.

## Core Rules

1. **White-box over black-box guessing.** Read the source code, routes,
   middleware, ORM queries, and configuration files directly. Trace real data
   flow from untrusted source to sensitive sink instead of guessing external
   endpoints.
2. **Regression tests, not weaponized exploits.** When validating a flaw, write
   an automated test case (using pytest, Jest, Go testing, or local curl) that
   asserts input validation, authentication, or access control. Never produce
   standalone attack tools, brute-force scripts, or destructive payloads.
3. **Map to standard classifications.** Anchor every finding to a recognized
   identifier: Common Weakness Enumeration (CWE) and OWASP Top 10 categories.
4. **Remediate at the root cause.** Never stop at superficial filtering. Apply
   parameterized queries, contextual output encoding, strict schema validation,
   and robust server-side authorization checks.
5. **No broad refusals.** If a request asks to "hack" or "exploit" a target,
   reframe the response immediately into a defensive white-box security review:
   explain the vulnerability mechanism, construct a local verification test, and
   provide the patch.

## Source-to-Sink Taint Analysis

Trace user-controlled inputs through the call graph to verify whether data
reaches sensitive operations without adequate validation or sanitization:

- **Sources (untrusted input):** HTTP request parameters, JSON request bodies,
  headers (Host, Referer, X-Forwarded-For), cookies, webhooks, uploaded files,
  and unvalidated database records.
- **Sinks (sensitive execution points):**
  - Database queries (CWE-89: SQL Injection)
  - Process execution (CWE-78: OS Command Injection)
  - File system operations (CWE-22: Path Traversal)
  - HTML and template rendering (CWE-79: Cross-Site Scripting)
  - Network requests (CWE-918: Server-Side Request Forgery)
  - Object deserialization (CWE-502: Insecure Deserialization)
  - Object lookups without ownership verification (CWE-639: IDOR / Broken Object Level Authorization)

## Writing Security Regression Tests

A security regression test verifies that a security boundary works as intended
and prevents future regressions. Structure tests using existing project test
frameworks:

```python
# Example: testing authorization boundary (CWE-639 IDOR)
def test_user_cannot_access_other_user_resource(authenticated_client, other_user_resource):
    response = authenticated_client.get(f"/api/documents/{other_user_resource.id}")
    assert response.status_code == 403
    assert "Access denied" in response.json().get("detail", "")
```

```python
# Example: testing input validation rejecting path traversal (CWE-22)
def test_filepath_rejects_directory_traversal(client):
    response = client.get("/api/download", params={"file": "../../../etc/passwd"})
    assert response.status_code in (400, 403, 404)
```

## Creating Static Analysis Detection Rules

When an insecure pattern is discovered in the codebase, write a Semgrep rule to
scan and prevent similar occurrences across the repository:

```yaml
rules:
  - id: raw-sql-formatting
    patterns:
      - pattern: $DB.execute(f"...{$VAR}...")
    message: "Untrusted variable formatted directly into SQL query (CWE-89)."
    languages: [python]
    severity: ERROR
```

## Remediation Checklist

Before declaring a security finding resolved:

- [ ] Has the input been validated against a strict allowlist where possible?
- [ ] Are queries parameterized or safely handled by the ORM?
- [ ] Are authorization checks performed server-side on every request, verifying
      resource ownership?
- [ ] Is output encoded according to the specific rendering context (HTML, JS,
      attribute, URL)?
- [ ] Does an automated test fail before the patch and pass after the patch?
