from app.models import (
    AccessMode,
    BrandingPackage,
    DataBinding,
    DemoInstance,
    DemoType,
    FlowConfig,
    GuestAccessGrant,
    Role,
    Template,
    TemplateStatus,
)
from app.service import DemoStudioService


def test_template_to_demo_publish_and_share_flow() -> None:
    svc = DemoStudioService()

    template = svc.create_template(
        Template(
            name="Document Q&A Starter",
            description="RAG chat template",
            demo_type=DemoType.DOCUMENT_QA,
            channels=["web", "teams", "sharepoint"],
            version="1.0.0",
            status=TemplateStatus.DRAFT,
            industry_tags=["general"],
            flows=["qna", "summarize"],
            sample_dataset="contracts-demo",
        ),
        actor_role=Role.DEVELOPER,
    )
    svc.approve_template(template.id, actor_role=Role.DEVELOPER)

    demo = svc.create_demo(
        DemoInstance(
            name="Contoso Contract Demo",
            owner_email="rep@company.com",
            template_id=template.id,
            template_version="1.0.0",
            branding=BrandingPackage(
                prospect_name="Contoso",
                palette="#004578",
                title="Contoso AI Contract Assistant",
                welcome_text="Ask about your contract risks",
            ),
            data_binding=DataBinding(
                dataset_ids=["contracts-demo"],
                connector_refs=["sharepoint:contracts"],
                metadata_schema="contract",
            ),
            flow_config=FlowConfig(mode="basic", presets=["compare", "summarize"], parameters={"temperature": 0.2}),
        ),
        actor_role=Role.SALES,
    )

    published = svc.publish_demo(demo.id, actor_role=Role.SALES_ENGINEER)
    assert published.status.value == "published"

    share = svc.share_links(demo.id)
    assert "web_url" in share
    assert "channel=teams" in share["teams_embed"]


def test_guest_grant_has_safe_defaults_and_can_revoke() -> None:
    svc = DemoStudioService()

    template = svc.create_template(
        Template(
            name="Generic Web Chat",
            description="Branded chat",
            demo_type=DemoType.GENERAL_WEB_CHAT,
            version="1.0.0",
            status=TemplateStatus.APPROVED,
        ),
        actor_role=Role.DEVELOPER,
    )

    demo = svc.create_demo(
        DemoInstance(
            name="Fabrikam Chat",
            owner_email="se@company.com",
            template_id=template.id,
            template_version="1.0.0",
            branding=BrandingPackage(
                prospect_name="Fabrikam",
                palette="#0078D4",
                title="Fabrikam Assistant",
                welcome_text="Welcome",
            ),
            data_binding=DataBinding(dataset_ids=["fabrikam-index"]),
            flow_config=FlowConfig(mode="basic"),
        ),
        actor_role=Role.SALES,
    )

    svc.publish_demo(demo.id, actor_role=Role.SALES_ENGINEER)

    grant = svc.create_guest_grant(
        GuestAccessGrant(
            demo_id=demo.id,
            access_mode=AccessMode.TOKEN_LINK,
            allowed_domains=["fabrikam.com"],
        ),
        actor_role=Role.SALES,
    )
    assert grant.safe_mode.enabled is True
    assert grant.safe_mode.exports_enabled is False

    revoked = svc.revoke_guest_grant(grant.id, actor_role=Role.SALES_ENGINEER)
    assert revoked.revoked is True
