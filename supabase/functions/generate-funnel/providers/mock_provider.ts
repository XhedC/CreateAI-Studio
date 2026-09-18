import type { FunnelGenerationProvider, FunnelProviderRequest } from "./provider.ts";
import type { ProviderFunnelResult } from "../types.ts";

/** Development-mode provider (default). Builds a complete, realistic funnel
 * document directly from the business fields the user typed - no external
 * network call, so it's always safe to leave enabled. Section selection
 * follows the same "pick sections based on the goal" rule a real LLM
 * provider is asked to follow, so mock and real output have the same shape.
 */
export class MockFunnelProvider implements FunnelGenerationProvider {
  async generate(request: FunnelProviderRequest): Promise<ProviderFunnelResult> {
    await new Promise((resolve) => setTimeout(resolve, 600));

    const { businessInfo, funnelType, prompt } = request;
    const name = businessInfo.businessName?.trim() || "Your Business";
    const product = businessInfo.product?.trim() || "our product or service";
    const audience = businessInfo.targetAudience?.trim() || "people who need it most";
    const offer = businessInfo.offer?.trim() || "a limited-time introductory offer";
    const cta = businessInfo.cta?.trim() || "Get Started";
    const goal = (businessInfo.goal ?? "custom").trim() || "custom";

    const headline = `${name}: ${product}, built for ${audience}`;
    const subheadline = prompt.trim() ||
      `Discover why ${audience} choose ${name} for ${product}.`;

    const sections: Record<string, unknown>[] = [
      {
        id: "hero-1",
        type: "hero",
        visible: true,
        content: {
          headline,
          subheadline,
          cta,
          image: null,
        },
      },
      {
        id: "benefits-1",
        type: "benefits",
        visible: true,
        content: {
          title: `Why choose ${name}`,
          items: [
            { title: "Trusted expertise", description: `Years of experience delivering ${product}.` },
            { title: "Made for you", description: `Tailored specifically for ${audience}.` },
            { title: "Real results", description: "A track record our customers can vouch for." },
          ],
        },
      },
      {
        id: "features-1",
        type: "features",
        visible: true,
        content: {
          title: "What you get",
          items: [
            { title: "Fast onboarding", description: "Get started in minutes, not weeks." },
            { title: "Dedicated support", description: "We're here whenever you need us." },
            { title: "Flexible options", description: "Choose what fits your needs best." },
          ],
        },
      },
      {
        id: "services-1",
        type: "services",
        visible: true,
        content: {
          title: "Our services",
          items: [
            { title: product, description: businessInfo.businessType?.trim() || "Our core offering." },
          ],
        },
      },
      {
        id: "testimonials-1",
        type: "testimonials",
        visible: true,
        content: {
          title: "What our customers say",
          items: [
            {
              quote: `${name} completely changed how we think about ${product}.`,
              author: "A happy customer",
            },
            {
              quote: "Placeholder testimonial - replace with a real customer quote.",
              author: "Placeholder",
            },
          ],
        },
      },
      {
        id: "faq-1",
        type: "faq",
        visible: true,
        content: {
          title: "Frequently asked questions",
          items: [
            { question: `What is ${product}?`, answer: subheadline },
            { question: "How do I get started?", answer: `Click "${cta}" to begin.` },
          ],
        },
      },
      {
        id: "contact-1",
        type: "contact",
        visible: true,
        content: {
          title: "Get in touch",
          description: `Have questions about ${product}? We'd love to hear from you.`,
        },
      },
    ];

    if (["generate_leads", "collect_contact_info", "custom"].includes(goal)) {
      sections.push({
        id: "lead-form-1",
        type: "lead_form",
        visible: true,
        content: { title: "Request more information", submitLabel: cta },
      });
    }
    if (["book_appointment", "event_registration"].includes(goal)) {
      sections.push({
        id: "appointment-1",
        type: "appointment_cta",
        visible: true,
        content: { title: "Book your appointment", cta: cta },
      });
    }
    if (["sell_product"].includes(goal) || funnelType === "ecommerce" || funnelType === "course") {
      sections.push({
        id: "pricing-1",
        type: "pricing",
        visible: true,
        content: {
          title: "Pricing",
          plans: [{ name: "Standard", price: offer, features: [product] }],
        },
      });
    }

    sections.push({
      id: "final-cta-1",
      type: "final_cta",
      visible: true,
      content: { headline: `Ready to get started with ${name}?`, cta },
    });
    sections.push({
      id: "footer-1",
      type: "footer",
      visible: true,
      content: { businessName: name, tagline: subheadline },
    });

    const raw = {
      name: `${name} Landing Page`,
      type: funnelType,
      metadata: {
        business_name: name,
        business_type: businessInfo.businessType ?? "",
        target_audience: audience,
        goal,
        offer,
        cta,
      },
      theme: {
        primaryColor: "#2563EB",
        secondaryColor: "#0F172A",
        backgroundColor: "#FFFFFF",
        textColor: "#0F172A",
        fontFamily: "Inter",
      },
      sections,
      seo: {
        title: `${name} - ${product}`,
        description: subheadline,
        ogTitle: `${name} - ${product}`,
        ogDescription: subheadline,
      },
      settings: {
        showNavigation: true,
        enableLeadCapture: sections.some((s) => s.type === "lead_form"),
      },
    };

    return {
      raw,
      providerName: "mock",
      modelName: "mock-funnel-v2",
      metadata: { mock: true, sectionsGenerated: sections.length },
    };
  }
}
