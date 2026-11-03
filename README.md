# Genie Usage & Cost Dashboard Accelerator

**TL;DR:** An AI/BI dashboard, packaged as a Declarative Automation Bundle (DAB), that shows Databricks
Genie LLM usage, cost, and user tiers across **Genie Code**, **Genie One**, and **Genie Agents**.
It reads only Databricks system tables. Clone this repo into a workspace Git folder, set your SQL
warehouse, and click **Deploy**. No local tools required.

## Executive summary

Genie is billed pay-as-you-go, with a free monthly allowance per user. Because Genie usage is agentic,
consumption varies widely between users, and a small share of users typically drives most of the spend.
This dashboard gives platform and FinOps teams the visibility recommended in the
[Genie consumption guide](https://docs.databricks.com/aws/en/genie/consumption-guide):

- **Who is using Genie and how much**, by product, user, and workspace.
- **What it costs**: billed spend, plus the value of today's free usage at post-promotion prices.
- **User tiers** (AI beginners, AI practitioners, AI power users) based on billed spend, as the basis
  for per-group [Genie budgets](https://docs.databricks.com/aws/en/genie/budgets) and forecasting.

This is Phase 1: Genie **LLM** costs. Compute that Genie triggers (for example, SQL warehouses that run
Genie-generated queries) is billed separately and is not included.

## What the dashboard shows

| # | Visual | Page | Chart type |
|---|---|---|---|
| 1 | Genie KPIs: billed spend, free usage at post-promo price, active users, messages | Overview | Counters with sparklines |
| 2 | Daily billed spend by product; daily DBUs billed vs. free | Overview | Stacked bars |
| 3 | Daily messages for the top 25 users | Users & Tiers | Heatmap |
| 4 | Daily and monthly active users by product | Overview | Line + grouped bar |
| 5 | Usage by workspace (top 15 by messages) | Overview | Bar + table |
| 6 | Share of users vs. share of billed spend by tier, with tier summary | Users & Tiers | Grouped horizontal bar + table |
| 7 | Tier mix by workspace | Users & Tiers | 100% stacked horizontal bar |
| 8 | Top 15 identities by billed spend, with spend detail | Cost Drivers | Ranked bar + table |

Global filters: **Date range** (default: last 30 days), **Workspace**, and **Genie product**.

## Architecture

```
system.billing.usage            Genie LLM usage (billing_origin_product = 'GENIE')
system.billing.account_prices   Your account's prices (used when available)
system.billing.list_prices      List prices (fallback)
system.access.assistant_events  Genie Code messages
system.access.audit             Genie Agents and Genie One messages
system.access.workspaces_latest Workspace names
            |
            v
8 dashboard datasets (SQL, filtered by the Date range parameter)
            |
            v
AI/BI dashboard: Overview | Users & Tiers | Cost Drivers | Filters
            ^
            |
databricks.yml (bundle) deploys the dashboard to your workspace
```

### Definitions

- **Billed spend:** Genie DBUs under the billed SKU x your account price (`system.billing.account_prices`),
  or list price (`system.billing.list_prices.pricing.effective_list.default`) if no account price exists.
  Through January 31, 2027, a 25% promotional discount applies to all billed Genie usage and is already
  built into the billed DBU counts.
- **Free usage at post-promo price:** free Genie DBUs (`GENIE_FREE_USAGE`, which has no price) priced at
  the workspace's billed Genie SKU, with no promotional discount, following
  [Monitor and understand your Genie cost](https://docs.databricks.com/aws/en/genie/monitor-cost).
  This is an estimate. It does not subtract any free monthly allowance.
- **Product:** `usage_metadata.genie.surface` (`GENIE_CODE`, `GENIE_ONE`, `GENIE_AGENTS`).
- **Messages:** Genie Code messages from `system.access.assistant_events`; Genie Agents messages (chat
  and agent mode, UI and API) and Genie One messages from `system.access.audit`.
- **Tiers** (human users, selected date range), named after the consumption guide's personas:
  - **AI beginners:** $0 billed (stayed within free usage)
  - **AI practitioners:** billed, at or below the 75th percentile of billed users
  - **AI power users:** billed, above the 75th percentile of billed users

## Prerequisites

- A Unity Catalog-enabled workspace with **workspace files** and **serverless compute** enabled
  (required for bundles in the workspace).
- A **SQL warehouse** (serverless recommended) that you can use.
- Access to the system tables listed above. By default only admins can read system tables; an account or
  metastore admin can grant `USE SCHEMA` and `SELECT` on `system.billing` and `system.access` to others.
- **Viewers** of the dashboard need the same system table access. The bundle sets
  `embed_credentials: false`, so each viewer's own permissions are used. See
  [Configuration](#configuration) to change this.

## Deploy from the Workspace UI (no local tools)

Based on [Clone a repo](https://docs.databricks.com/aws/en/repos/git-operations-with-repos) and
[Deploy bundles from the workspace](https://docs.databricks.com/aws/en/dev-tools/bundles/workspace-deploy).

1. **Create a Git folder from this repo**
   1. In the sidebar, click **Workspace** and browse to your user folder (`/Workspace/Users/<you>`).
   2. Click **Create > Git folder**.
   3. For **Git repository URL**, enter
      `https://github.com/ryan-rabold-databricks/genie-usage-cost-accelerator.git`.
      Set **Git provider** to **GitHub**, keep the default folder name, and click **Create Git folder**.

   Public repositories can be cloned without Git credentials. If your workspace requires them, see
   [Connect your Git provider to Databricks](https://docs.databricks.com/aws/en/repos/repos-setup).

2. **Choose your SQL warehouse**
   1. In the Git folder, open `databricks.yml`.
   2. Under `variables > warehouse_id > lookup`, replace `Serverless Starter Warehouse` with the
      **name** of a SQL warehouse in your workspace (see **SQL Warehouses** in the sidebar).
   3. The file saves automatically.

3. **Deploy the bundle**
   1. With `databricks.yml` open, click the **deployments** icon to open the **Deployments** pane.
   2. Choose a target:
      - **dev** (default): a personal copy for review. Its name is prefixed with `[dev <your name>]`.
      - **prod**: the shared copy for your team.
   3. Click **Deploy**, review the validation details, then click **Deploy** again.
   4. When it finishes, the dashboard appears under **Bundle resources**. Click it to open it.

4. **Share the dashboard**
   Use **Share** on the dashboard to give your team access. Remember that viewers also need access to
   the system tables (see Prerequisites).

To pick up a newer version of this accelerator, pull the latest changes into the Git folder (Git dialog >
**Pull**) and deploy again.

## Deploy with the Databricks CLI (alternative)

Requires a recent Databricks CLI (dashboard resources need v0.232.0 or later).

```bash
git clone https://github.com/ryan-rabold-databricks/genie-usage-cost-accelerator.git
cd genie-usage-cost-accelerator
# Edit the warehouse name in databricks.yml, then:
databricks bundle validate --target prod --profile <your-profile>
databricks bundle deploy   --target prod --profile <your-profile>
```

## Project structure

```
genie-usage-cost-accelerator/
├── databricks.yml                     # Bundle: warehouse variable, dashboard resource, dev/prod targets
├── README.md
└── src/
    ├── genie_usage_cost.lvdash.json   # Dashboard definition (deployed by the bundle)
    └── sql/                           # Readable copy of each dataset's SQL, for review
        ├── ds_spend_daily.sql
        ├── ds_activity_daily.sql
        ├── ds_workspace_usage.sql
        ├── ds_user_heatmap.sql
        ├── ds_user_tiers.sql
        ├── ds_tier_summary.sql
        ├── ds_top_users.sql
        └── ds_cost_drivers.sql
```

The files in `src/sql/` are for review only. The dashboard runs the SQL embedded in
`genie_usage_cost.lvdash.json`.

## Configuration

| Setting | Where | Default |
|---|---|---|
| SQL warehouse | `databricks.yml` > `variables.warehouse_id.lookup.warehouse` | `Serverless Starter Warehouse` |
| Dashboard name | `databricks.yml` > `resources.dashboards.genie_usage_cost.display_name` | `Genie Usage & Cost` |
| Viewer credentials | `databricks.yml` > `embed_credentials` | `false` (viewers use their own access) |
| Default date range | Dashboard **Filters** page, or the `period` parameter in the dashboard JSON | Last 30 days |

**About `embed_credentials`:** setting it to `true` runs every viewer's queries with the deploying
user's permissions. Viewers then see billing and audit data without their own system table access.
Only do this if everyone you share the dashboard with should see that data.

No environment variables are required.

## Limitations

- Genie LLM billing has no dashboard ID or query type.
- Team rollups need a user-to-team mapping (for example, from identity provider groups). Visual 7
  uses each user's primary workspace as an interim proxy.
- Free usage under `GENIE_FREE_USAGE` is visible from July 20, 2026 onward.
- `system.access.assistant_events` is in Public Preview. Before May 7, 2026 it also logged background
  requests, so earlier Genie Code message counts are inflated.
- In very large accounts, the audit-log scans can take several minutes on a small warehouse. Use a
  larger warehouse or a shorter date range.

## Disclaimer

This accelerator is provided as-is as community content and is not an officially supported Databricks
product. Figures are estimates computed from system tables. Validate them against your actual billing
before relying on them.
