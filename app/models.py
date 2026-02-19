from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Any
from uuid import UUID, uuid4


class Role(str, Enum):
    SALES = "sales"
    SALES_ENGINEER = "sales_engineer"
    DEVELOPER = "developer"
    ADMIN = "admin"


class DemoType(str, Enum):
    DOCUMENT_QA = "document_qa"
    CONTRACT_ANALYSIS = "contract_analysis"
    UNSTRUCTURED_EXTRACTION = "unstructured_extraction"
    GENERAL_WEB_CHAT = "general_web_chat"
    DASHBOARD_CHAT = "dashboard_chat"
    CHATGPT_APP = "chatgpt_app"


class TemplateStatus(str, Enum):
    DRAFT = "draft"
    APPROVED = "approved"
    PUBLISHED = "published"


class DemoStatus(str, Enum):
    DRAFT = "draft"
    PUBLISHED = "published"
    ARCHIVED = "archived"


class AccessMode(str, Enum):
    INVITE_ONLY = "invite_only"
    TOKEN_LINK = "token_link"


@dataclass
class SafeDemoMode:
    enabled: bool = True
    read_only_tools: bool = True
    exports_enabled: bool = False
    limit_verbatim_quoting: bool = True
    prompt_injection_hardening: bool = True
    store_full_transcripts: bool = False


@dataclass
class BrandingPackage:
    prospect_name: str
    palette: str
    title: str
    welcome_text: str
    logo_url: str | None = None
    cta_text: str | None = None


@dataclass
class DataBinding:
    dataset_ids: list[str]
    connector_refs: list[str] = field(default_factory=list)
    metadata_schema: str = "default"
    retention_days: int = 14


@dataclass
class FlowConfig:
    mode: str
    presets: list[str] = field(default_factory=list)
    parameters: dict[str, Any] = field(default_factory=dict)
    allowed_tools: list[str] = field(default_factory=lambda: ["retrieval"])


@dataclass
class Template:
    name: str
    description: str
    demo_type: DemoType
    version: str
    channels: list[str] = field(default_factory=lambda: ["web"])
    status: TemplateStatus = TemplateStatus.DRAFT
    complexity: str = "basic"
    industry_tags: list[str] = field(default_factory=list)
    flows: list[str] = field(default_factory=list)
    sample_dataset: str | None = None
    id: UUID = field(default_factory=uuid4)


@dataclass
class DemoInstance:
    name: str
    owner_email: str
    template_id: UUID
    template_version: str
    branding: BrandingPackage
    data_binding: DataBinding
    flow_config: FlowConfig
    status: DemoStatus = DemoStatus.DRAFT
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    id: UUID = field(default_factory=uuid4)


@dataclass
class GuestAccessGrant:
    demo_id: UUID
    access_mode: AccessMode
    expires_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc) + timedelta(days=14))
    allowed_emails: list[str] = field(default_factory=list)
    allowed_domains: list[str] = field(default_factory=list)
    max_sessions: int = 3
    max_requests_per_session: int = 50
    max_daily_tokens: int = 50_000
    max_daily_cost_usd: float = 10.0
    safe_mode: SafeDemoMode = field(default_factory=SafeDemoMode)
    revoked: bool = False
    id: UUID = field(default_factory=uuid4)


@dataclass
class ChatGPTAppRecord:
    name: str
    description: str
    deep_link_url: str
    usage_instructions: str
    talk_track: str
    owner_email: str
    tags: list[str] = field(default_factory=list)
    recommended_prompts: list[str] = field(default_factory=list)
    lifecycle_status: str = "draft"
    id: UUID = field(default_factory=uuid4)


@dataclass
class AnalyticsSnapshot:
    demo_id: UUID
    sessions: int = 0
    return_visits: int = 0
    top_actions: dict[str, int] = field(default_factory=dict)
    errors: int = 0
    avg_latency_ms: float = 0.0
    token_cost_usd: float = 0.0
