-- Dataset: Top users by day (ds_user_heatmap)
-- :period.min / :period.max are the dashboard's Date range filter.
WITH
genie_messages AS (
  SELECT
    CAST(e.event_date AS DATE) AS event_date,
    e.workspace_id,
    e.initiated_by AS user_name,
    'Genie Code' AS product,
    'Genie Code' AS mode,
    'UI' AS channel
  FROM system.access.assistant_events e
  WHERE CAST(e.event_date AS DATE) BETWEEN :period.min AND :period.max
  UNION ALL
  SELECT
    a.event_date,
    a.workspace_id,
    COALESCE(a.user_identity.email, a.user_identity.subject_name) AS user_name,
    CASE a.service_name WHEN 'aibiGenie' THEN 'Genie Agents' ELSE 'Genie One' END AS product,
    CASE
      WHEN a.action_name IN ('createAgenticResponse', 'genieCreateAgenticResponse') THEN 'Agent mode'
      WHEN a.service_name = 'aibiGenie' THEN 'Chat mode'
      ELSE 'Genie One chat'
    END AS mode,
    CASE WHEN a.service_name = 'aibiGenie' AND a.action_name LIKE 'genie%' THEN 'API' ELSE 'UI' END AS channel
  FROM system.access.audit a
  WHERE a.event_date BETWEEN :period.min AND :period.max
    AND a.response.status_code = 200
    AND (
      (a.service_name = 'aibiGenie' AND a.action_name IN (
          'createConversationMessage', 'createAgenticResponse',
          'genieStartConversationMessage', 'genieCreateConversationMessage',
          'genieCreateAgenticResponse'))
      OR (a.service_name = 'genieChat' AND a.action_name = 'createGenieChatResponse')
    )
),
top_users AS (
  SELECT user_name FROM genie_messages
  WHERE user_name LIKE '%@%'
  GROUP BY user_name ORDER BY COUNT(*) DESC LIMIT 25
)
SELECT m.event_date, date_format(m.event_date, 'MM-dd') AS day_label, m.user_name, COUNT(*) AS messages
FROM genie_messages m
JOIN top_users t ON t.user_name = m.user_name
GROUP BY ALL
ORDER BY m.event_date
