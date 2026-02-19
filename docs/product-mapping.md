# Requirement Mapping (MVP)

## Demo types
The API models the requested phase-1 types:
- `document_qa`
- `contract_analysis`
- `unstructured_extraction`
- `general_web_chat`
- `dashboard_chat`
- `chatgpt_app`

## Governance and lifecycle
- Templates: `draft -> approved -> published`
- Demos: `draft -> published -> archived`
- Role checks on endpoints: Sales, Sales Engineer, Developer, Admin

## Guest access controls
`GuestAccessGrant` includes:
- expiry (`expires_at` default 14 days)
- allow-lists (`allowed_emails`, `allowed_domains`)
- limits (`max_sessions`, `max_requests_per_session`)
- budgets (`max_daily_tokens`, `max_daily_cost_usd`)
- revocation (`revoked` flag)

## Safe Demo Mode defaults
Enabled by default with:
- read-only tools only
- exports disabled
- verbatim quotation limit enabled
- injection hardening enabled
- transcript storage disabled

## Channels
Share endpoint returns:
- web route (`/d/{demoId}`)
- Teams embed route (`/embed?...channel=teams`)
- SharePoint embed route (`/embed?...channel=sharepoint`)

## Analytics scaffold
Per-demo snapshot currently exposes:
- sessions, return visits
- top actions
- errors and latency
- token/cost metric
