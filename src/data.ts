export type Template = {
  id: string;
  name: string;
  description: string;
  status: "draft" | "approved" | "published";
};

export type DemoInstance = {
  id: string;
  templateId: string;
  name: string;
  ownerEmail: string;
  status: "draft" | "published";
};

const templates: Template[] = [
  {
    id: "document-qa-starter",
    name: "Document Q&A Starter",
    description: "RAG chat template",
    status: "approved",
  },
  {
    id: "generic-web-chat",
    name: "Generic Web Chat",
    description: "Branded chat",
    status: "approved",
  },
];

export function listApprovedTemplates(): Template[] {
  return templates.filter((template) => template.status !== "draft");
}

export function createDemoFromTemplate(
  templateId: string,
  name: string,
  ownerEmail: string,
): DemoInstance {
  return {
    id: crypto.randomUUID(),
    templateId,
    name,
    ownerEmail,
    status: "published",
  };
}
