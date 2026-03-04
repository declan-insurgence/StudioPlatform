import json
import os
import urllib.error
import urllib.request

import pytest


def test_cloudflare_account_token_verify_live() -> None:
    if os.getenv("RUN_CLOUDFLARE_LIVE_TESTS") != "1":
        pytest.skip("Set RUN_CLOUDFLARE_LIVE_TESTS=1 to run live Cloudflare token verification.")

    account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID")
    token = os.getenv("CLOUDFLARE_API_TOKEN")
    if not account_id or not token:
        pytest.skip("Set CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN in .env for this live test.")

    request = urllib.request.Request(
        url=f"https://api.cloudflare.com/client/v4/accounts/{account_id}/tokens/verify",
        headers={"Authorization": f"Bearer {token}"},
    )

    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            assert response.status == 200
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        pytest.fail(f"Cloudflare verify endpoint returned HTTP {exc.code}")
    except urllib.error.URLError as exc:
        pytest.fail(f"Could not reach Cloudflare verify endpoint: {exc.reason}")

    assert payload.get("success") is True
    assert payload.get("errors") == []
    assert payload.get("result", {}).get("status") == "active"
