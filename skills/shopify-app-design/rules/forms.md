# Forms & Inputs

## Form Components

Every form input component supports `label`, `name`, `helpText`, and `error` props.

### Text Inputs

```html
<!-- s-text-field -->
<s-text-field
  label="Product title"
  name="title"
  help-text="Give your product a short, descriptive title"
></s-text-field>

<!-- s-text-area -->
<s-text-area
  label="Description"
  name="description"
  help-text="Describe your product in detail"
  rows="4"
></s-text-area>

<!-- s-email-field -->
<s-email-field
  label="Customer email"
  name="email"
  help-text="We'll send order confirmations here"
></s-email-field>

<!-- s-password-field -->
<s-password-field
  label="API secret"
  name="secret"
></s-password-field>

<!-- s-url-field -->
<s-url-field
  label="Website URL"
  name="website"
  help-text="Include https://"
></s-url-field>

<!-- s-search-field -->
<s-search-field
  label="Search products"
  name="search"
></s-search-field>
```

### Numeric & Money Inputs

```html
<!-- s-number-field -->
<s-number-field
  label="Quantity"
  name="quantity"
  min="0"
  step="1"
  help-text="How many items to restock"
></s-number-field>

<!-- s-money-field -->
<s-money-field
  label="Price"
  name="price"
  currency="USD"
  help-text="Set the selling price"
></s-money-field>
```

### Selection Inputs

```html
<!-- s-select -->
<s-select
  label="Product type"
  name="type"
  help-text="Choose the category that fits best"
>
  <option value="physical">Physical product</option>
  <option value="digital">Digital product</option>
  <option value="service">Service</option>
</s-select>

<!-- s-checkbox -->
<s-checkbox
  label="This product has a SKU"
  name="hasSku"
  help-text="Stock Keeping Unit for inventory tracking"
></s-checkbox>

<!-- s-switch -->
<s-switch
  label="Enable inventory tracking"
  name="trackInventory"
  help-text="Automatically update stock levels"
></s-switch>

<!-- s-choice-list -->
<s-choice-list
  label="Shipping options"
  name="shipping"
  help-text="Select all that apply"
>
  <s-choice value="standard">Standard shipping</s-choice>
  <s-choice value="express">Express shipping</s-choice>
  <s-choice value="pickup">Local pickup</s-choice>
</s-choice-list>
```

### Date, Color & File Inputs

```html
<!-- s-date-field -->
<s-date-field
  label="Publish date"
  name="publishDate"
  help-text="When this product becomes visible"
></s-date-field>

<!-- s-color-field -->
<s-color-field
  label="Theme color"
  name="themeColor"
  help-text="Pick a brand color for this collection"
></s-color-field>

<!-- s-drop-zone -->
<s-drop-zone
  label="Product images"
  name="images"
  help-text="Upload up to 10 images (PNG, JPG)"
></s-drop-zone>
```

### Error States on Components

```html
<!-- Any component with an error -->
<s-text-field
  label="Product title"
  name="title"
  error="Product title is required"
></s-text-field>

<s-number-field
  label="Weight"
  name="weight"
  error="Enter a weight greater than 0"
></s-number-field>

<s-select
  label="Status"
  name="status"
  error="Choose a status to continue"
>
  <option value="">Select a status</option>
  <option value="active">Active</option>
  <option value="draft">Draft</option>
</s-select>
```

---

## Save Bar

The save bar appears automatically when a form with `data-save-bar` has unsaved changes.

```html
<!-- Default: save bar on form -->
<form data-save-bar>
  <s-text-field label="Shop name" name="shopName"></s-text-field>
  <s-text-area label="Shop description" name="shopDescription"></s-text-area>
</form>
```

```html
<!-- With discard confirmation dialog -->
<form data-save-bar data-discard-confirmation>
  <s-text-field label="Shop name" name="shopName"></s-text-field>
</form>
```

```javascript
// Programmatic save bar control
shopify.saveBar.show();
shopify.saveBar.hide();
shopify.saveBar.toggle();
```

Default to save bar for detail/edit pages. Auto-save may be used where it aligns with Shopify admin patterns (e.g., simple toggles, inline edits).

---

## Validation

### Inline Errors

Show errors AFTER blur, never during typing.

```jsx
// ✅ DO: Show error on blur
function ProductForm() {
  const [title, setTitle] = useState("");
  const [titleError, setTitleError] = useState("");

  return (
    <s-text-field
      label="Product title"
      name="title"
      value={title}
      error={titleError}
      onBlur={() => {
        if (!title.trim()) {
          setTitleError("Product title is required");
        }
      }}
      onChange={(e) => {
        setTitle(e.target.value);
        if (titleError) setTitleError("");
      }}
    />
  );
}
```

```jsx
// ❌ DON'T: Show error while user is still typing
function ProductForm() {
  const [title, setTitle] = useState("");

  return (
    <s-text-field
      label="Product title"
      name="title"
      value={title}
      error={!title.trim() ? "Product title is required" : ""}
      onChange={(e) => setTitle(e.target.value)}
    />
  );
}
```

### Page-Level Error Banners

Place banners near the top of the affected section, not in modals.

```html
<!-- ✅ DO: Banner at top of section -->
<s-page heading="Edit product">
  <s-banner tone="critical">
    There were 2 errors with your submission. Fix the highlighted fields below.
  </s-banner>

  <s-section>
    <s-text-field label="Title" name="title" error="Title is required" />
    <s-number-field label="Price" name="price" error="Enter a valid price" />
  </s-section>
</s-page>
```

```html
<!-- ❌ DON'T: Error banners inside modals (except modal-specific errors) -->
<s-modal>
  <s-banner tone="critical">Something went wrong</s-banner>
  <s-text-field label="Name" name="name" />
</s-modal>
```

### Error Writing

```text
✅ "Enter a price greater than 0"
✅ "Product title is required"
✅ "This email address isn't valid. Check the format and try again."

❌ "INVALID INPUT ERROR: field validation failed (code 422)"
❌ "CRITICAL: This field cannot be empty!"
❌ "Bad value"
```

No jargon. No scary language. Always offer a path forward.

---

## Organization

### Section Forms

Use `s-section` with a heading when a form has 5+ inputs.

```html
<!-- ✅ DO: Group related fields in sections -->
<s-page heading="Edit product">
  <s-section>
    <s-section heading="Basic information">
      <s-text-field label="Title" name="title"></s-text-field>
      <s-text-area label="Description" name="description"></s-text-area>
      <s-select label="Type" name="type">
        <option value="physical">Physical</option>
        <option value="digital">Digital</option>
      </s-select>
    </s-section>

    <s-section heading="Pricing">
      <s-money-field label="Price" name="price" currency="USD"></s-money-field>
      <s-money-field label="Compare at price" name="comparePrice" currency="USD"></s-money-field>
      <s-checkbox label="Charge tax" name="taxable"></s-checkbox>
    </s-section>

    <s-section heading="Inventory">
      <s-text-field label="SKU" name="sku"></s-text-field>
      <s-number-field label="Quantity" name="quantity"></s-number-field>
      <s-switch label="Track inventory" name="trackInventory"></s-switch>
    </s-section>
  </s-section>
</s-page>
```

```html
<!-- ❌ DON'T: Large forms inside modals -->
<s-modal title="Create product">
  <s-text-field label="Title" name="title"></s-text-field>
  <s-text-area label="Description" name="description"></s-text-area>
  <s-money-field label="Price" name="price"></s-money-field>
  <s-text-field label="SKU" name="sku"></s-text-field>
  <s-number-field label="Quantity" name="quantity"></s-number-field>
  <s-select label="Type" name="type">...</s-select>
  <s-checkbox label="Taxable" name="taxable"></s-checkbox>
  <s-switch label="Track inventory" name="trackInventory"></s-switch>
</s-modal>
```

Never put large forms in modals — create a new page instead. One entity per page.

---

## Progressive Disclosure

Conditionally reveal fields based on prior input.

```jsx
// ✅ DO: Show fields only when relevant
function ShippingForm() {
  const [trackInventory, setTrackInventory] = useState(false);

  return (
    <>
      <s-switch
        label="Track inventory"
        name="trackInventory"
        checked={trackInventory}
        onChange={(e) => setTrackInventory(e.target.checked)}
      />

      {trackInventory && (
        <>
          <s-number-field label="Quantity" name="quantity" />
          <s-text-field label="SKU" name="sku" />
          <s-select label="Warehouse" name="warehouse">
            <option value="us">US warehouse</option>
            <option value="eu">EU warehouse</option>
          </s-select>
        </>
      )}
    </>
  );
}
```

```jsx
// ❌ DON'T: Show all fields at once with disabled states
function ShippingForm() {
  const [trackInventory, setTrackInventory] = useState(false);

  return (
    <>
      <s-switch label="Track inventory" name="trackInventory" />
      <s-number-field label="Quantity" name="quantity" disabled={!trackInventory} />
      <s-text-field label="SKU" name="sku" disabled={!trackInventory} />
      <s-select label="Warehouse" name="warehouse" disabled={!trackInventory}>
        <option value="us">US warehouse</option>
        <option value="eu">EU warehouse</option>
      </s-select>
    </>
  );
}
```

---

## Controlled vs Uncontrolled

Use `value` for controlled and `defaultValue` for uncontrolled. All form elements return string values — parse numbers manually.

```jsx
// ✅ DO: Controlled with manual number parsing
function PriceForm() {
  const [price, setPrice] = useState("10.00");

  const handleSubmit = () => {
    const numericPrice = parseFloat(price);
    if (isNaN(numericPrice)) return;
    save({ price: numericPrice });
  };

  return (
    <s-text-field
      label="Price"
      name="price"
      value={price}
      onChange={(e) => setPrice(e.target.value)}
    />
  );
}
```

```jsx
// ✅ DO: Uncontrolled with defaultValue
function SettingsForm() {
  return (
    <form data-save-bar>
      <s-text-field
        label="Shop name"
        name="shopName"
        defaultValue="My Shop"
      />
    </form>
  );
}
```

```jsx
// ❌ DON'T: Assume numeric return types
function QuantityForm() {
  const handleChange = (e) => {
    const quantity = e.target.value + 1; // Bug: "5" + 1 = "51"
    updateStock(quantity);
  };

  return (
    <s-number-field
      label="Quantity"
      name="quantity"
      onChange={handleChange}
    />
  );
}
```

---

## React Router Patterns

Use `useFetcher()` for form submissions with loading and error states.

```jsx
// ✅ DO: useFetcher for form submission
import { useFetcher } from "react-router";

function ProductForm({ product }) {
  const fetcher = useFetcher();
  const isSubmitting = fetcher.state === "submitting";
  const errors = fetcher.data?.errors;

  return (
    <fetcher.Form method="post" data-save-bar data-discard-confirmation>
      {errors?.general && (
        <s-banner tone="critical">{errors.general}</s-banner>
      )}

      <s-section>
        <s-text-field
          label="Title"
          name="title"
          defaultValue={product.title}
          error={errors?.title}
        />
        <s-text-area
          label="Description"
          name="description"
          defaultValue={product.description}
          error={errors?.description}
        />
      </s-section>
    </fetcher.Form>
  );
}
```

```jsx
// ❌ DON'T: Manual fetch with useState for forms
function ProductForm({ product }) {
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState({});

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    const res = await fetch("/api/products", {
      method: "POST",
      body: new FormData(e.target),
    });
    const data = await res.json();
    setLoading(false);
    if (data.errors) setErrors(data.errors);
  };

  return (
    <form onSubmit={handleSubmit}>
      <s-text-field label="Title" name="title" />
      <button type="submit" disabled={loading}>Save</button>
    </form>
  );
}
```
