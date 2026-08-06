# Settings Page Template

**When to use:** App configuration page. Loader returns the current settings object; action handler persists changes.

**Data shape:**

```typescript
interface SettingsData {
  settings: {
    storeName: string;
    emailNotifications: boolean;
    orderAlerts: boolean;
    alertEmail: string;
    theme: string;
    autoSync: boolean;
    syncInterval: string;
    enabledMarkets: string[];
  };
}
```

**Complete route file:**

```tsx
import type { LoaderFunctionArgs, ActionFunctionArgs } from "react-router";
import { useLoaderData, useFetcher } from "react-router";
import { authenticate } from "../shopify.server";

export const loader = async ({ request }: LoaderFunctionArgs) => {
  const { admin } = await authenticate.admin(request);

  // Replace with actual settings fetch
  const settings = {
    storeName: "My Store",
    emailNotifications: true,
    orderAlerts: false,
    alertEmail: "alerts@example.com",
    theme: "default",
    autoSync: true,
    syncInterval: "15",
    enabledMarkets: ["us", "ca"],
  };

  return { settings };
};

export const action = async ({ request }: ActionFunctionArgs) => {
  const { admin } = await authenticate.admin(request);
  const formData = await request.formData();

  const settings = {
    storeName: formData.get("storeName") as string,
    emailNotifications: formData.get("emailNotifications") === "on",
    orderAlerts: formData.get("orderAlerts") === "on",
    alertEmail: formData.get("alertEmail") as string,
    theme: formData.get("theme") as string,
    autoSync: formData.get("autoSync") === "on",
    syncInterval: formData.get("syncInterval") as string,
  };

  // await saveSettings(settings);

  return { success: true, error: null };
};

export default function SettingsPage() {
  const { settings } = useLoaderData<typeof loader>();
  const fetcher = useFetcher<{ success?: boolean; error?: string | null }>();

  const isSubmitting = fetcher.state !== "idle";

  return (
    <s-page heading="Settings">
      {/* Success/error banner */}
      {fetcher.data?.success && (
        <s-banner tone="success" dismissible>
          Settings saved successfully.
        </s-banner>
      )}
      {fetcher.data?.error && (
        <s-banner tone="critical" dismissible>
          {fetcher.data.error}
        </s-banner>
      )}

      <fetcher.Form method="post" data-save-bar>
        {/* General settings */}
        <s-section heading="General">
          <s-text-field
            label="Store name"
            name="storeName"
            defaultValue={settings.storeName}
            helpText="This name appears in customer-facing communications."
            autoComplete="off"
          />
          <s-select
            label="Theme"
            name="theme"
            defaultValue={settings.theme}
            helpText="Choose the visual theme for your app widgets."
          >
            <option value="default">Default</option>
            <option value="minimal">Minimal</option>
            <option value="bold">Bold</option>
          </s-select>
        </s-section>

        {/* Notification settings */}
        <s-section heading="Notifications">
          <s-switch
            label="Email notifications"
            name="emailNotifications"
            defaultChecked={settings.emailNotifications}
            helpText="Receive email updates about your store activity."
          />
          <s-switch
            label="Order alerts"
            name="orderAlerts"
            defaultChecked={settings.orderAlerts}
            helpText="Get notified when a new order is placed."
          />
          <s-text-field
            label="Alert email address"
            name="alertEmail"
            type="email"
            defaultValue={settings.alertEmail}
            helpText="Where order alerts and notifications are sent."
            autoComplete="email"
          />
        </s-section>

        {/* Advanced settings */}
        <s-section heading="Advanced">
          <s-switch
            label="Auto-sync"
            name="autoSync"
            defaultChecked={settings.autoSync}
            helpText="Automatically sync inventory data at the selected interval."
          />
          <s-select
            label="Sync interval"
            name="syncInterval"
            defaultValue={settings.syncInterval}
            helpText="How often inventory data is synchronized."
          >
            <option value="5">Every 5 minutes</option>
            <option value="15">Every 15 minutes</option>
            <option value="30">Every 30 minutes</option>
            <option value="60">Every hour</option>
          </s-select>
          <s-checkbox
            label="United States"
            name="market-us"
            defaultChecked={settings.enabledMarkets.includes("us")}
          />
          <s-checkbox
            label="Canada"
            name="market-ca"
            defaultChecked={settings.enabledMarkets.includes("ca")}
          />
          <s-checkbox
            label="European Union"
            name="market-eu"
            defaultChecked={settings.enabledMarkets.includes("eu")}
          />
        </s-section>

        {/* Submit */}
        <s-box padding="400">
          <s-button variant="primary" type="submit" loading={isSubmitting}>
            Save settings
          </s-button>
        </s-box>
      </fetcher.Form>
    </s-page>
  );
}
```
