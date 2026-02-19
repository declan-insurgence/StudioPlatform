from __future__ import annotations

from uuid import UUID, uuid4

from .models import AnalyticsSnapshot, ChatGPTAppRecord, DemoInstance, DemoStatus, GuestAccessGrant, Template, TemplateStatus


class InMemoryStore:
    def __init__(self) -> None:
        self.templates: dict[UUID, Template] = {}
        self.demos: dict[UUID, DemoInstance] = {}
        self.grants: dict[UUID, GuestAccessGrant] = {}
        self.chatgpt_apps: dict[UUID, ChatGPTAppRecord] = {}
        self.analytics: dict[UUID, AnalyticsSnapshot] = {}

    def create_template(self, template: Template) -> Template:
        self.templates[template.id] = template
        return template

    def list_templates(self, *, only_approved: bool = False, demo_type: str | None = None) -> list[Template]:
        templates = list(self.templates.values())
        if only_approved:
            templates = [t for t in templates if t.status in {TemplateStatus.APPROVED, TemplateStatus.PUBLISHED}]
        if demo_type:
            templates = [t for t in templates if t.demo_type.value == demo_type]
        return templates

    def create_demo(self, demo: DemoInstance) -> DemoInstance:
        self.demos[demo.id] = demo
        self.analytics[demo.id] = AnalyticsSnapshot(demo_id=demo.id)
        return demo

    def clone_demo(self, demo_id: UUID, new_name: str, owner_email: str) -> DemoInstance:
        source = self.demos[demo_id]
        clone = DemoInstance(
            id=uuid4(),
            name=new_name,
            owner_email=owner_email,
            template_id=source.template_id,
            template_version=source.template_version,
            status=DemoStatus.DRAFT,
            branding=source.branding,
            data_binding=source.data_binding,
            flow_config=source.flow_config,
        )
        return self.create_demo(clone)

    def publish_demo(self, demo_id: UUID) -> DemoInstance:
        demo = self.demos[demo_id]
        demo.status = DemoStatus.PUBLISHED
        return demo

    def create_grant(self, grant: GuestAccessGrant) -> GuestAccessGrant:
        self.grants[grant.id] = grant
        return grant

    def revoke_grant(self, grant_id: UUID) -> GuestAccessGrant:
        grant = self.grants[grant_id]
        grant.revoked = True
        return grant

    def add_chatgpt_app(self, app: ChatGPTAppRecord) -> ChatGPTAppRecord:
        self.chatgpt_apps[app.id] = app
        return app
