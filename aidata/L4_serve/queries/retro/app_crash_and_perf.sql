-- 7-day crash signature novelty, crash-free rate, and P95 latency regression (>20%) across personal apps.
WITH anchor AS (
    SELECT COALESCE(
        (SELECT MAX(cst_day) FROM fact_product_telemetry),
        date('now', '+8 hours')
    ) AS max_day
),
window_7d AS (
    SELECT *
    FROM fact_product_telemetry, anchor
    WHERE app_name IN ('AIDash', 'VitalStride', 'VoxPocket', 'Financial')
      AND cst_day > date(anchor.max_day, '-7 days')
      AND cst_day <= anchor.max_day
),
window_prev_7d AS (
    SELECT *
    FROM fact_product_telemetry, anchor
    WHERE app_name IN ('AIDash', 'VitalStride', 'VoxPocket', 'Financial')
      AND cst_day > date(anchor.max_day, '-14 days')
      AND cst_day <= date(anchor.max_day, '-7 days')
),
prior_signatures AS (
    SELECT DISTINCT app_name, COALESCE(signature, '') AS sig
    FROM fact_product_telemetry, anchor
    WHERE app_name IN ('AIDash', 'VitalStride', 'VoxPocket', 'Financial')
      AND event_kind = 'crash'
      AND cst_day <= date(anchor.max_day, '-7 days')
),
app_counts AS (
    SELECT
        app_name,
        MAX(platform) AS platform,
        COUNT(*) AS total_events_7d,
        SUM(CASE WHEN event_kind = 'crash' THEN 1 ELSE 0 END) AS crash_count_7d,
        ROUND(
            1.0 - (
                1.0 * SUM(CASE WHEN event_kind = 'crash' THEN 1 ELSE 0 END)
                / NULLIF(COUNT(*), 0)
            ),
            4
        ) AS crash_free_rate_7d
    FROM window_7d
    GROUP BY app_name
),
new_crash_sigs AS (
    SELECT
        w.app_name,
        w.signature,
        MAX(w.stack_top_symbol) AS stack_top_symbol,
        COUNT(*) AS sig_count
    FROM window_7d AS w
    LEFT JOIN prior_signatures AS p
      ON p.app_name = w.app_name AND p.sig = COALESCE(w.signature, '')
    WHERE w.event_kind = 'crash'
      AND p.sig IS NULL
    GROUP BY w.app_name, w.signature
),
new_crash_summary AS (
    SELECT
        app_name,
        COUNT(*) AS new_crash_signature_count,
        (
            SELECT n2.signature
            FROM new_crash_sigs AS n2
            WHERE n2.app_name = n1.app_name
            ORDER BY n2.sig_count DESC, n2.signature ASC
            LIMIT 1
        ) AS top_new_signature,
        (
            SELECT n2.stack_top_symbol
            FROM new_crash_sigs AS n2
            WHERE n2.app_name = n1.app_name
            ORDER BY n2.sig_count DESC, n2.signature ASC
            LIMIT 1
        ) AS top_crash_symbol
    FROM new_crash_sigs AS n1
    GROUP BY app_name
),
perf_7d_sig_ranked AS (
    SELECT
        app_name,
        COALESCE(signature, 'default_perf') AS perf_sig,
        metric_ms,
        stack_top_symbol,
        ROW_NUMBER() OVER (
            PARTITION BY app_name, COALESCE(signature, 'default_perf')
            ORDER BY metric_ms ASC
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY app_name, COALESCE(signature, 'default_perf')
        ) AS cnt
    FROM window_7d
    WHERE event_kind = 'perf' AND metric_ms IS NOT NULL
),
perf_7d_by_sig AS (
    SELECT
        app_name,
        perf_sig,
        ROUND(MIN(metric_ms), 2) AS p95_metric_ms_7d,
        MAX(stack_top_symbol) AS perf_stack_top_symbol
    FROM perf_7d_sig_ranked
    WHERE rn = CAST((cnt * 95 + 99) / 100 AS INTEGER)
    GROUP BY app_name, perf_sig
),
perf_prev_sig_ranked AS (
    SELECT
        app_name,
        COALESCE(signature, 'default_perf') AS perf_sig,
        metric_ms,
        ROW_NUMBER() OVER (
            PARTITION BY app_name, COALESCE(signature, 'default_perf')
            ORDER BY metric_ms ASC
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY app_name, COALESCE(signature, 'default_perf')
        ) AS cnt
    FROM window_prev_7d
    WHERE event_kind = 'perf' AND metric_ms IS NOT NULL
),
perf_prev_by_sig AS (
    SELECT
        app_name,
        perf_sig,
        ROUND(MIN(metric_ms), 2) AS p95_metric_ms_prev_7d
    FROM perf_prev_sig_ranked
    WHERE rn = CAST((cnt * 95 + 99) / 100 AS INTEGER)
    GROUP BY app_name, perf_sig
),
perf_joined AS (
    SELECT
        cur.app_name,
        cur.perf_sig AS perf_signature,
        cur.perf_stack_top_symbol,
        cur.p95_metric_ms_7d,
        prev.p95_metric_ms_prev_7d,
        ROUND(
            CASE
                WHEN prev.p95_metric_ms_prev_7d IS NOT NULL AND prev.p95_metric_ms_prev_7d > 0
                THEN ((cur.p95_metric_ms_7d - prev.p95_metric_ms_prev_7d) * 100.0) / prev.p95_metric_ms_prev_7d
                ELSE 0.0
            END,
            2
        ) AS reg_pct,
        ROW_NUMBER() OVER (
            PARTITION BY cur.app_name
            ORDER BY
                CASE
                    WHEN prev.p95_metric_ms_prev_7d IS NOT NULL AND prev.p95_metric_ms_prev_7d > 0
                    THEN ((cur.p95_metric_ms_7d - prev.p95_metric_ms_prev_7d) * 100.0) / prev.p95_metric_ms_prev_7d
                    ELSE -1e9
                END DESC,
                cur.p95_metric_ms_7d DESC,
                cur.perf_sig ASC
        ) AS sig_rank
    FROM perf_7d_by_sig AS cur
    LEFT JOIN perf_prev_by_sig AS prev
      ON prev.app_name = cur.app_name AND prev.perf_sig = cur.perf_sig
),
perf_7d_p95 AS (
    SELECT
        app_name,
        p95_metric_ms_7d,
        p95_metric_ms_prev_7d,
        perf_stack_top_symbol,
        perf_signature
    FROM perf_joined
    WHERE sig_rank = 1
),
perf_prev_p95 AS (
    SELECT
        app_name,
        p95_metric_ms_prev_7d
    FROM perf_7d_p95
)
SELECT
    c.app_name,
    c.platform,
    c.total_events_7d,
    c.crash_count_7d,
    COALESCE(nc.new_crash_signature_count, 0) AS new_crash_signature_count,
    c.crash_free_rate_7d,
    COALESCE(
        nc.top_new_signature,
        (
            SELECT w.signature FROM window_7d AS w
            WHERE w.app_name = c.app_name AND w.event_kind = 'crash'
            ORDER BY w.occurred_at DESC LIMIT 1
        ),
        p7.perf_signature
    ) AS signature,
    COALESCE(
        nc.top_crash_symbol,
        (
            SELECT w.stack_top_symbol FROM window_7d AS w
            WHERE w.app_name = c.app_name AND w.event_kind = 'crash' AND w.stack_top_symbol IS NOT NULL
            ORDER BY w.occurred_at DESC LIMIT 1
        ),
        p7.perf_stack_top_symbol
    ) AS stack_top_symbol,
    p7.p95_metric_ms_7d,
    pp.p95_metric_ms_prev_7d,
    ROUND(
        CASE
            WHEN pp.p95_metric_ms_prev_7d IS NOT NULL AND pp.p95_metric_ms_prev_7d > 0
                 AND p7.p95_metric_ms_7d IS NOT NULL
            THEN ((p7.p95_metric_ms_7d - pp.p95_metric_ms_prev_7d) * 100.0) / pp.p95_metric_ms_prev_7d
            ELSE 0.0
        END,
        2
    ) AS p95_regression_pct,
    CASE
        WHEN pp.p95_metric_ms_prev_7d IS NOT NULL AND pp.p95_metric_ms_prev_7d > 0
             AND p7.p95_metric_ms_7d IS NOT NULL
             AND ((p7.p95_metric_ms_7d - pp.p95_metric_ms_prev_7d) * 100.0) / pp.p95_metric_ms_prev_7d > 20.0
        THEN 1
        ELSE 0
    END AS is_perf_regressed
FROM app_counts AS c
LEFT JOIN new_crash_summary AS nc ON nc.app_name = c.app_name
LEFT JOIN perf_7d_p95 AS p7 ON p7.app_name = c.app_name
LEFT JOIN perf_prev_p95 AS pp ON pp.app_name = c.app_name
ORDER BY COALESCE(nc.new_crash_signature_count, 0) DESC, is_perf_regressed DESC, c.app_name ASC;
