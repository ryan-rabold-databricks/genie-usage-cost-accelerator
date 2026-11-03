-- Dataset: Cost drivers detail (ds_cost_drivers)
-- :period.min / :period.max are the dashboard's Date range filter.
WITH
genie_rows AS (
  SELECT
    u.usage_date,
    u.workspace_id,
    u.account_id,
    u.cloud,
    u.sku_name,
    u.usage_unit,
    u.usage_end_time,
    u.identity_metadata.run_as AS user_name,
    CASE WHEN u.identity_metadata.run_as LIKE '%@%' THEN 'User' ELSE 'Service principal' END AS principal_type,
    CASE u.usage_metadata.genie.surface
      WHEN 'GENIE_CODE'   THEN 'Genie Code'
      WHEN 'GENIE_ONE'    THEN 'Genie One'
      WHEN 'GENIE_AGENTS' THEN 'Genie Agents'
      ELSE COALESCE(u.usage_metadata.genie.surface, 'Other')
    END AS product,
    COALESCE(u.usage_metadata.genie.channel, 'UNKNOWN') AS channel,
    CASE WHEN u.sku_name = 'GENIE_FREE_USAGE' THEN 'Free' ELSE 'Billed' END AS billing_type,
    u.usage_quantity AS dbus
  FROM system.billing.usage u
  WHERE u.billing_origin_product = 'GENIE'
    AND u.usage_date BETWEEN :period.min AND :period.max
),
genie_priced AS (
  SELECT
    r.*,
    CASE WHEN r.billing_type = 'Billed'
         THEN COALESCE(ap.pricing.default, lp.pricing.effective_list.default) END AS billed_unit_price_usd,
    CASE WHEN r.billing_type = 'Billed'
         THEN r.dbus * COALESCE(ap.pricing.default, lp.pricing.effective_list.default)
         ELSE 0 END AS billed_cost_usd
  FROM genie_rows r
  LEFT JOIN system.billing.account_prices ap
    ON  ap.account_id = r.account_id
    AND ap.sku_name = r.sku_name
    AND ap.cloud = r.cloud
    AND ap.usage_unit = r.usage_unit
    AND ap.currency_code = 'USD'
    AND r.usage_end_time >= ap.price_start_time
    AND (ap.price_end_time IS NULL OR r.usage_end_time < ap.price_end_time)
  LEFT JOIN system.billing.list_prices lp
    ON  lp.sku_name = r.sku_name
    AND lp.cloud = r.cloud
    AND lp.usage_unit = r.usage_unit
    AND lp.currency_code = 'USD'
    AND r.usage_end_time >= lp.price_start_time
    AND (lp.price_end_time IS NULL OR r.usage_end_time < lp.price_end_time)
),
proxy_sku AS (
  SELECT workspace_id, MAX_BY(sku_name, usage_end_time) AS sku_name
  FROM genie_rows WHERE billing_type = 'Billed' GROUP BY workspace_id
),
proxy_sku_cloud AS (
  SELECT cloud, MAX_BY(sku_name, usage_end_time) AS sku_name
  FROM genie_rows WHERE billing_type = 'Billed' GROUP BY cloud
),
free_priced AS (
  SELECT
    f.workspace_id,
    f.cloud,
    f.account_id,
    COALESCE(ps.sku_name, pc.sku_name) AS proxy_sku_name
  FROM (SELECT DISTINCT workspace_id, cloud, account_id FROM genie_rows WHERE billing_type = 'Free') f
  LEFT JOIN proxy_sku ps ON ps.workspace_id = f.workspace_id
  LEFT JOIN proxy_sku_cloud pc ON pc.cloud = f.cloud
),
free_unit_price AS (
  SELECT
    fp.workspace_id,
    COALESCE(ap.pricing.default, lp.pricing.effective_list.default) AS usd_per_dbu
  FROM free_priced fp
  LEFT JOIN system.billing.account_prices ap
    ON  ap.account_id = fp.account_id AND ap.sku_name = fp.proxy_sku_name AND ap.cloud = fp.cloud
    AND ap.currency_code = 'USD' AND ap.price_end_time IS NULL
  LEFT JOIN system.billing.list_prices lp
    ON  lp.sku_name = fp.proxy_sku_name AND lp.cloud = fp.cloud
    AND lp.currency_code = 'USD' AND lp.price_end_time IS NULL
),
genie_costed AS (
  SELECT
    p.*,
    CASE WHEN p.billing_type = 'Free'
         THEN p.dbus * fup.usd_per_dbu
         ELSE 0 END AS est_free_value_usd,
    CASE WHEN p.billing_type = 'Billed' THEN p.billed_unit_price_usd ELSE fup.usd_per_dbu END AS unit_price_usd
  FROM genie_priced p
  LEFT JOIN free_unit_price fup ON fup.workspace_id = p.workspace_id
),
workspaces AS (
  SELECT workspace_id, workspace_name FROM system.access.workspaces_latest
),
period_days AS (
  SELECT GREATEST(DATEDIFF(LEAST(CAST(:period.max AS DATE), current_date()), CAST(:period.min AS DATE)) + 1, 1) AS days
)
SELECT
  c.user_name,
  c.principal_type,
  COALESCE(w.workspace_name, CAST(c.workspace_id AS STRING)) AS workspace_name,
  c.product,
  c.channel,
  SUM(CASE WHEN c.billing_type = 'Billed' THEN c.dbus ELSE 0 END) AS billed_dbus,
  SUM(CASE WHEN c.billing_type = 'Free'   THEN c.dbus ELSE 0 END) AS free_dbus,
  SUM(c.billed_cost_usd) AS billed_cost_usd,
  SUM(c.est_free_value_usd) AS est_free_value_usd
FROM genie_costed c
LEFT JOIN workspaces w ON w.workspace_id = c.workspace_id
GROUP BY ALL
ORDER BY billed_cost_usd DESC, free_dbus DESC
LIMIT 500
