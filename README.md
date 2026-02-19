# Demo Studio Platform (MVP)

Demo Studio is an internal sales enablement platform for rapidly assembling branded AI demos from governed templates.

This MVP provides a backend API aligned to the CEO draft requirements:
- Template gallery + approval workflow
- Demo instance creation, cloning, and publishing
- Web + Teams/SharePoint embed link generation
- Guest access grants with **Safe Demo Mode** defaults
- ChatGPT external app registry + deep-link metadata
- Per-demo analytics endpoint scaffold

## Quick start

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
uvicorn app.main:app --reload
```

## Test

```bash
pytest
```

## API highlights

- `POST /templates` – create template (Developer/Admin)
- `POST /templates/{id}/approve` – approve template
- `POST /demos` – create demo from approved template (Sales/SE/Admin)
- `POST /demos/{id}/publish` – publish demo (SE/Admin)
- `GET /demos/{id}/share` – web + embed URLs
- `POST /guest-grants` – create guest grant with expiry/budgets/safe mode
- `POST /guest-grants/{id}/revoke` – revoke guest access immediately
- `POST /chatgpt-apps` – register external ChatGPT app
- `GET /analytics/{demo_id}` – engagement/cost snapshot
