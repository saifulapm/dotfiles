# Onboarding Template

**When to use:** First-time setup flow. Maximum 5 steps. Loader returns step data and completion state.

**Data shape:**

```typescript
interface OnboardingData {
  steps: Array<{
    id: string;
    title: string;
    description: string;
    completed: boolean;
  }>;
  currentStep: number;
  totalSteps: number;
}
```

**Complete route file:**

```tsx
import type { LoaderFunctionArgs, ActionFunctionArgs } from "react-router";
import { redirect } from "react-router";
import { useLoaderData, useFetcher } from "react-router";
import { authenticate } from "../shopify.server";

export const loader = async ({ request }: LoaderFunctionArgs) => {
  const { admin } = await authenticate.admin(request);

  // Replace with actual onboarding state fetch
  const steps = [
    {
      id: "connect-store",
      title: "Connect your store",
      description: "Link your Shopify store to enable product syncing.",
      completed: true,
    },
    {
      id: "import-products",
      title: "Import products",
      description: "Select which products to manage with this app.",
      completed: false,
    },
    {
      id: "configure-rules",
      title: "Configure pricing rules",
      description: "Set up automatic pricing rules for your products.",
      completed: false,
    },
    {
      id: "review",
      title: "Review and launch",
      description: "Review your setup and activate the app.",
      completed: false,
    },
  ];

  // Current step is the first incomplete step
  const currentStep = steps.findIndex((s) => !s.completed);
  const totalSteps = steps.length;

  return {
    steps,
    currentStep: currentStep === -1 ? totalSteps : currentStep,
    totalSteps,
  };
};

export const action = async ({ request }: ActionFunctionArgs) => {
  const { admin } = await authenticate.admin(request);
  const formData = await request.formData();
  const intent = formData.get("intent");

  if (intent === "dismiss") {
    // Mark onboarding as dismissed, redirect to main app
    // await dismissOnboarding(session.shop);
    return redirect("/app");
  }

  if (intent === "complete-step") {
    const stepId = formData.get("stepId") as string;
    // await completeOnboardingStep(session.shop, stepId);
    return { success: true };
  }

  return { success: false };
};

export default function OnboardingPage() {
  const { steps, currentStep, totalSteps } = useLoaderData<typeof loader>();
  const fetcher = useFetcher();

  const allComplete = currentStep >= totalSteps;

  return (
    <s-page heading="Get started">
      {/* Welcome banner */}
      <s-banner tone="info" dismissible>
        Welcome! Complete these steps to set up your app. It only takes a few
        minutes.
      </s-banner>

      {/* Progress indicator */}
      <s-section>
        <s-text variant="headingSm" as="p">
          Step {Math.min(currentStep + 1, totalSteps)} of {totalSteps}
        </s-text>
        <s-text variant="bodySm" tone="subdued" as="p">
          {steps.filter((s) => s.completed).length} of {totalSteps} completed
        </s-text>
      </s-section>

      {/* Step list */}
      <s-section heading="Setup steps">
        {steps.map((step, index) => {
          const isCurrent = index === currentStep;
          const isFuture = index > currentStep;

          return (
            <s-box
              key={step.id}
              padding="400"
              border-block-end="base"
              background={isCurrent ? "bg-surface-secondary" : undefined}
            >
              <s-grid columns="1 1 3">
                <s-box>
                  {/* Completion badge */}
                  {step.completed ? (
                    <s-badge tone="success">Complete</s-badge>
                  ) : isCurrent ? (
                    <s-badge tone="attention">Current</s-badge>
                  ) : (
                    <s-badge>Pending</s-badge>
                  )}
                </s-box>
                <s-box>
                  <s-text
                    variant="headingSm"
                    as="h3"
                    tone={isFuture ? "subdued" : undefined}
                  >
                    {step.title}
                  </s-text>
                  <s-text
                    variant="bodySm"
                    tone={isFuture ? "subdued" : undefined}
                  >
                    {step.description}
                  </s-text>

                  {/* CTA for current step */}
                  {isCurrent && (
                    <s-box padding-block-start="300">
                      <fetcher.Form method="post">
                        <input type="hidden" name="intent" value="complete-step" />
                        <input type="hidden" name="stepId" value={step.id} />
                        <s-button
                          variant="primary"
                          type="submit"
                          loading={fetcher.state !== "idle"}
                        >
                          {step.title}
                        </s-button>
                      </fetcher.Form>
                    </s-box>
                  )}
                </s-box>
              </s-grid>
            </s-box>
          );
        })}
      </s-section>

      {/* All complete state */}
      {allComplete && (
        <s-section>
          <s-banner tone="success">
            You're all set! Your app is ready to use.
          </s-banner>
          <s-box padding-block-start="400">
            <s-button variant="primary" url="/app">
              Go to dashboard
            </s-button>
          </s-box>
        </s-section>
      )}

      {/* Dismiss / remind me later */}
      {!allComplete && (
        <s-box padding="400">
          <fetcher.Form method="post">
            <input type="hidden" name="intent" value="dismiss" />
            <s-button variant="plain" type="submit">
              Remind me later
            </s-button>
          </fetcher.Form>
        </s-box>
      )}
    </s-page>
  );
}
```
