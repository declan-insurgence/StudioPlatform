from __future__ import annotations

from uuid import UUID

from .models import ChatGPTAppRecord, DemoInstance, DemoStatus, GuestAccessGrant, Role, Template, TemplateStatus
from .store import InMemoryStore


class PermissionDenied(Exception):
    pass


class ValidationError(Exception):
    pass


class NotFoundError(Exception):
    pass


class DemoStudioService:
    def __init__(self, store: InMemoryStore | None = None) -> None:
        self.store = store or InMemoryStore()

    def create_template(self, template: Template, actor_role: Role) -> Template:
        if actor_role not in {Role.DEVELOPER, Role.ADMIN}:
            raise PermissionDenied("Only developer/admin can create templates")
        return self.store.create_template(template)

    def approve_template(self, template_id: UUID, actor_role: Role) -> Template:
        if actor_role not in {Role.DEVELOPER, Role.ADMIN}:
            raise PermissionDenied("Only developer/admin can approve templates")
        template = self.store.templates.get(template_id)
        if not template:
            raise NotFoundError("Template not found")
        template.status = TemplateStatus.APPROVED
        return template

    def create_demo(self, demo: DemoInstance, actor_role: Role) -> DemoInstance:
        if actor_role not in {Role.SALES, Role.SALES_ENGINEER, Role.ADMIN}:
            raise PermissionDenied("Sales/SE/Admin required")
        template = self.store.templates.get(demo.template_id)
        if not template or template.status == TemplateStatus.DRAFT:
            raise ValidationError("Template must be approved")
        return self.store.create_demo(demo)

    def publish_demo(self, demo_id: UUID, actor_role: Role) -> DemoInstance:
        if actor_role not in {Role.SALES_ENGINEER, Role.ADMIN}:
            raise PermissionDenied("SE/Admin required")
        if demo_id not in self.store.demos:
            raise NotFoundError("Demo not found")
        return self.store.publish_demo(demo_id)

    def share_links(self, demo_id: UUID) -> dict[str, str]:
        demo = self.store.demos.get(demo_id)
        if not demo or demo.status != DemoStatus.PUBLISHED:
            raise ValidationError("Demo must be published")
        return {
            "web_url": f"https://demo.yourdomain/d/{demo.id}",
            "teams_embed": f"https://demo.yourdomain/embed?demoId={demo.id}&channel=teams",
            "sharepoint_embed": f"https://demo.yourdomain/embed?demoId={demo.id}&channel=sharepoint",
        }

    def create_guest_grant(self, grant: GuestAccessGrant, actor_role: Role) -> GuestAccessGrant:
        if actor_role not in {Role.SALES, Role.SALES_ENGINEER, Role.ADMIN}:
            raise PermissionDenied("Sales/SE/Admin required")
        demo = self.store.demos.get(grant.demo_id)
        if not demo or demo.status != DemoStatus.PUBLISHED:
            raise ValidationError("Published demo required")
        return self.store.create_grant(grant)

    def revoke_guest_grant(self, grant_id: UUID, actor_role: Role) -> GuestAccessGrant:
        if actor_role not in {Role.SALES_ENGINEER, Role.ADMIN}:
            raise PermissionDenied("SE/Admin required")
        if grant_id not in self.store.grants:
            raise NotFoundError("Grant not found")
        return self.store.revoke_grant(grant_id)

    def register_chatgpt_app(self, record: ChatGPTAppRecord, actor_role: Role) -> ChatGPTAppRecord:
        if actor_role not in {Role.SALES_ENGINEER, Role.ADMIN}:
            raise PermissionDenied("SE/Admin required")
        return self.store.add_chatgpt_app(record)
