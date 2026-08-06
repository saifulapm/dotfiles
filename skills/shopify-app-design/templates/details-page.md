# Details Page Template

**When to use:** View/edit a single resource. Loader returns the resource object; action handler processes updates and deletes.

**Data shape:**

```typescript
interface DetailsData {
  item: {
    id: string;
    title: string;
    description: string;
    price: string;
    status: string;
  };
}
```

**Complete route file:**

```tsx
import type { LoaderFunctionArgs, ActionFunctionArgs } from "react-router";
import { redirect } from "react-router";
import { useLoaderData, useFetcher } from "react-router";
import { authenticate } from "../shopify.server";
import { useState, useEffect } from "react";

export const loader = async ({ request, params }: LoaderFunctionArgs) => {
  const { admin } = await authenticate.admin(request);
  const { id } = params;

  // Replace with actual data fetching
  const item = {
    id: id!,
    title: "Summer campaign",
    description: "Promote summer collection with 20% off.",
    price: "49.99",
    status: "active",
  };

  return { item };
};

export const action = async ({ request, params }: ActionFunctionArgs) => {
  const { admin } = await authenticate.admin(request);
  const formData = await request.formData();
  const intent = formData.get("intent");

  if (intent === "delete") {
    // Delete the resource
    // await deleteItem(params.id);
    return redirect("/app/campaigns");
  }

  // Update the resource
  const title = formData.get("title") as string;
  const description = formData.get("description") as string;
  const price = formData.get("price") as string;
  const status = formData.get("status") as string;

  // await updateItem(params.id, { title, description, price, status });

  return { success: true };
};

export default function DetailsPage() {
  const { item } = useLoaderData<typeof loader>();
  const fetcher = useFetcher<{ success?: boolean }>();
  const [showDeleteModal, setShowDeleteModal] = useState(false);

  const isSubmitting = fetcher.state !== "idle";

  // Optimistic UI: use submitted values while saving
  const optimisticItem = fetcher.formData
    ? {
        ...item,
        title: (fetcher.formData.get("title") as string) || item.title,
        description: (fetcher.formData.get("description") as string) || item.description,
        price: (fetcher.formData.get("price") as string) || item.price,
        status: (fetcher.formData.get("status") as string) || item.status,
      }
    : item;

  // Show success toast on save
  useEffect(() => {
    if (fetcher.data?.success) {
      shopify.toast.show("Campaign saved");
    }
  }, [fetcher.data]);

  return (
    <s-page heading={optimisticItem.title}>
      {/* Back navigation */}
      <s-link slot="breadcrumb-actions" url="/app/campaigns">
        Campaigns
      </s-link>

      {/* Primary action */}
      <s-button
        slot="primary-action"
        variant="primary"
        form="details-form"
        type="submit"
        loading={isSubmitting}
      >
        Save
      </s-button>

      {/* Secondary actions */}
      <s-button
        slot="secondary-actions"
        variant="plain"
        tone="critical"
        onClick={() => setShowDeleteModal(true)}
      >
        Delete
      </s-button>

      {/* Main form with save bar */}
      <fetcher.Form
        method="post"
        id="details-form"
        data-save-bar
        data-discard-confirmation
      >
        {/* Details section */}
        <s-section heading="Details">
          <s-text-field
            label="Title"
            name="title"
            defaultValue={optimisticItem.title}
            autoComplete="off"
          />
          <s-text-field
            label="Description"
            name="description"
            defaultValue={optimisticItem.description}
            multiline={4}
            autoComplete="off"
          />
        </s-section>

        {/* Pricing section */}
        <s-section heading="Pricing">
          <s-text-field
            label="Price"
            name="price"
            type="number"
            defaultValue={optimisticItem.price}
            prefix="$"
            autoComplete="off"
          />
        </s-section>

        {/* Status section */}
        <s-section heading="Status">
          <s-select
            label="Status"
            name="status"
            defaultValue={optimisticItem.status}
          >
            <option value="active">Active</option>
            <option value="draft">Draft</option>
            <option value="archived">Archived</option>
          </s-select>
        </s-section>
      </fetcher.Form>

      {/* Delete confirmation modal */}
      {showDeleteModal && (
        <s-modal heading="Delete campaign?" open>
          <s-text>
            Are you sure you want to delete "{optimisticItem.title}"? This action
            cannot be undone.
          </s-text>
          <fetcher.Form method="post" slot="actions">
            <s-button
              variant="plain"
              onClick={() => setShowDeleteModal(false)}
            >
              Cancel
            </s-button>
            <input type="hidden" name="intent" value="delete" />
            <s-button variant="primary" tone="critical" type="submit">
              Delete campaign
            </s-button>
          </fetcher.Form>
        </s-modal>
      )}
    </s-page>
  );
}
```
