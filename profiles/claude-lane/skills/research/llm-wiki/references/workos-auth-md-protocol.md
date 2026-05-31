# WorkOS auth.md: Open Agent Registration Protocol

**Source**: MarkTechPost — "WorkOS Releases auth.md: An Open Agent Registration Protocol Built on OAuth Standards" (2026-05-26)
**Protocol spec**: https://workos.com/auth-md

## Overview

auth.md is an open protocol (not tied to WorkOS infrastructure) that enables AI agents to register with web services and obtain scoped credentials using existing OAuth standards (RFC 9728, ID-JAG).

## What is auth.md?

A plain-text Markdown file at `https://service.com/auth.md` — dual-purpose:
- Human-readable documentation for developers
- Machine-readable runtime artifact agents can parse programmatically

## Discovery (Two-Hop)

1. API returns **401** → header: `WWW-Authenticate: Bearer resource_metadata="https://api.service.com/.well-known/oauth-protected-resource"`
2. Agent fetches **`/.well-known/oauth-protected-resource`** → points to Authorization Server
3. Agent fetches **`/.well-known/oauth-authorization-server`** → reads `agent_auth` block: `register_uri`, `claim_uri`, `revocation_uri`, `identity_types_supported`

## Registration Flows

### Flow 1: Agent Verified (ID-JAG Based)
No human interaction. Agent's identity provider (OpenAI, Anthropic, Cursor) attests to user identity.

Steps: consent → request ID-JAG from provider → POST to `/agent/auth` → verify JWKS + claims → return credentials.

**Constraints:** No refresh tokens; fresh ID-JAG to extend; delegation per `(iss, sub, aud)`; requires provider ID-JAG support.

### Flow 2: User Claimed (OTP Based)
No provider needed. Email-based one-time passwords.

| Feature | Anonymous Start | Email Required |
|---------|----------------|----------------|
| Registration | Without identity | Email at registration |
| Credential timing | Immediate (pre-claim scopes) | Withheld until OTP verified |
| Pre-claim usage | Allowed | Not allowed |
| OTP ceremony | Later to bind user | Required before issuance |
| Key rotation | Scopes upgrade in place | Fresh credential on `/claim/complete` |

Endpoints: `POST /agent/auth/claim` (trigger OTP), `POST /agent/auth/claim/complete` (submit code)

## Credential Types

| Type | Flow | Behavior |
|------|------|----------|
| `access_token` | ID-JAG | No refresh token; fresh ID-JAG to extend |
| `api_key` | Anonymous/Email | Non-expiring; scopes upgrade after OTP claim |

On 401 from previously-working credential → drop and restart discovery.

## User Matching & JIT Provisioning

Resolution order: (1) delegation record `(iss, sub)`, (2) verified email match, (3) JIT provision or reject.

## Audit Events

`registration.created`, `claim.requested`, `otp.generated`, `claim.confirmed`, `registration.expired`, `registration.revoked`. Include `iss`, `sub`, `agent_platform` for ID-JAG flows.

## Related Wiki Pages

- [[workos]] — entity page
- [[auth-md-protocol]] — concept page
- [[oauth-bridge-pattern]] — related OAuth pattern for self-hosted services
