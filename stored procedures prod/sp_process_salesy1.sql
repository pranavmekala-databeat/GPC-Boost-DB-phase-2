CREATE OR REPLACE PROCEDURE public.sp_process_salesy1()
LANGUAGE plpgsql
AS $BODY$
    DECLARE
        v_row_count INTEGER;
        v_timestamp TIMESTAMP := (NOW() AT TIME ZONE 'Australia/Sydney');
        v_log_id BIGINT;
        v_start_time TIMESTAMPTZ := (NOW() AT TIME ZONE 'Australia/Sydney');
        v_end_time TIMESTAMPTZ;
        v_duration_ms BIGINT;
    BEGIN
        -- Log procedure start
        INSERT INTO execution_log (job_name, status, start_time)
        VALUES ('sp_process_salesy1', 'STARTED', v_start_time)
        RETURNING id INTO v_log_id;

        RAISE NOTICE 'Processing tSalesY1 at %', v_timestamp;

        BEGIN
            --------------------------------------------------------------------
            -- Step 1: Deduplicate temp data
            --------------------------------------------------------------------
            WITH deduped AS (
                SELECT DISTINCT ON (company, "salesType", sku)
                    company,
                    "salesType",
                    sku,
                    "costOfGoods",
                    sales,
                    margin,
                    "salesQuantity12",
                    "salesQuantity11",
                    "salesQuantity10",
                    "salesQuantity9",
                    "salesQuantity8",
                    "salesQuantity7",
                    "salesQuantity6",
                    "salesQuantity5",
                    "salesQuantity4",
                    "salesQuantity3",
                    "salesQuantity2",
                    "salesQuantity1",
                    "salesQuantity0",
                    "salesGroup1",
                    "salesGroup2",
                    "salesGroup3",
                    "salesGroup4",
                    "salesGroup5",
                    "salesGroup6",
                    "salesNSW",
                    "salesVIC",
                    "salesQLD",
                    "salesSA",
                    "salesWA",
                    "salesNT",
                    "salesTAS",
                    "averageSales12Months",
                    "averageSales9Months",
                    "averageSales6Months",
                    "averageSales3Months",
                    "storesSold",
                    country
                FROM public."tSalesY1_temp"
                ORDER BY company, "salesType", sku
            ),

            --------------------------------------------------------------------
            -- Step 2: Join with tProducts to get merchandisingGroup
            --------------------------------------------------------------------
            with_product_info AS (
                SELECT
                    d.*,
                    p."merchandisingGroup"
                FROM deduped d
                LEFT JOIN public."tProducts" p
                    ON d.sku = p.sku AND d.country = p.country
            ),

            --------------------------------------------------------------------
            -- Step 3: Compute calculated fields (Sales Hits & Average)
            --------------------------------------------------------------------
            computed AS (
                SELECT
                    d.*,
                    ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)
                    ) AS "salesHits12Months",
                    ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                     (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)
                    ) AS "salesHits6Months",
                    ROUND(
                        CASE
                            -- Scenario 1: CONSUMER + CASH + 12 hits (exact)
                            WHEN "merchandisingGroup" = 'CONSUMER'
                                 AND "salesType" = 'CASH'
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) = 12
                            THEN GREATEST(
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6" + "salesQuantity7" + "salesQuantity8" + "salesQuantity9" + "salesQuantity10" + "salesQuantity11" +
  "salesQuantity12") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                         ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                         ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 5
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) - 5.0),
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"),
                                         ("salesQuantity4"), ("salesQuantity5"), ("salesQuantity6")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 2
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) - 2.0)
                            )

                            -- Scenario 2: CONSUMER + CASH + ≥10 hits (12m) AND ≥5 hits (6m)
                            WHEN "merchandisingGroup" = 'CONSUMER'
                                 AND "salesType" = 'CASH'
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) >= 10
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) >= 5
                            THEN GREATEST(
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6" + "salesQuantity7" + "salesQuantity8" + "salesQuantity9" + "salesQuantity10" + "salesQuantity11" +
  "salesQuantity12") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                         ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                         ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 4
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) - 4.0),
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"),
                                         ("salesQuantity4"), ("salesQuantity5"), ("salesQuantity6")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 2
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) - 2.0)
                            )

                            -- Scenario 3: CONSUMER + CASH + ≥8 hits (12m) AND ≥4 hits (6m)
                            WHEN "merchandisingGroup" = 'CONSUMER'
                                 AND "salesType" = 'CASH'
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) >= 8
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) >= 4
                            THEN GREATEST(
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6" + "salesQuantity7" + "salesQuantity8" + "salesQuantity9" + "salesQuantity10" + "salesQuantity11" +
  "salesQuantity12") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                         ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                         ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 3
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) - 3.0),
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"),
                                         ("salesQuantity4"), ("salesQuantity5"), ("salesQuantity6")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 1
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) - 1.0)
                            )

                            -- Scenario 4: CONSUMER + CASH + ≥6 hits (12m) AND ≥4 hits (6m)
                            WHEN "merchandisingGroup" = 'CONSUMER'
                                 AND "salesType" = 'CASH'
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) >= 6
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) >= 4
                            THEN GREATEST(
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6" + "salesQuantity7" + "salesQuantity8" + "salesQuantity9" + "salesQuantity10" + "salesQuantity11" +
  "salesQuantity12") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                         ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                         ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 2
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) - 2.0),
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"),
                                         ("salesQuantity4"), ("salesQuantity5"), ("salesQuantity6")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 1
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) - 1.0)
                            )

                            -- Scenario 5: Any product with ≥10 hits (12m) and ≥5 hits (6m)
                            WHEN ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) >= 10
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) >= 5
                            THEN GREATEST(
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6" + "salesQuantity7" + "salesQuantity8" + "salesQuantity9" + "salesQuantity10" + "salesQuantity11" +
  "salesQuantity12") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                         ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                         ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 3
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) - 3.0),
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"),
                                         ("salesQuantity4"), ("salesQuantity5"), ("salesQuantity6")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 2
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) - 2.0)
                            )

                            -- Scenario 6: Any product with ≥8 hits (12m) and ≥4 hits (6m)
                            WHEN ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) >= 8
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) >= 4
                            THEN GREATEST(
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6" + "salesQuantity7" + "salesQuantity8" + "salesQuantity9" + "salesQuantity10" + "salesQuantity11" +
  "salesQuantity12") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                         ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                         ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 2
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) - 2.0),
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"),
                                         ("salesQuantity4"), ("salesQuantity5"), ("salesQuantity6")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 1
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) - 1.0)
                            )

                            -- Scenario 7: Any product with ≥6 hits (12m) and ≥4 hits (6m)
                            WHEN ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) >= 6
                                 AND ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) >= 4
                            THEN GREATEST(
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6" + "salesQuantity7" + "salesQuantity8" + "salesQuantity9" + "salesQuantity10" + "salesQuantity11" +
  "salesQuantity12") -
                                 (SELECT SUM(val) FROM (
                                     SELECT val FROM (VALUES
                                         ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                         ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                         ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                     ) AS t(val)
                                     ORDER BY val DESC
                                     LIMIT 1
                                 ) AS top_vals)
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) - 1.0),
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6") -
                                 (SELECT MAX(val) FROM (VALUES
                                     ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"),
                                     ("salesQuantity4"), ("salesQuantity5"), ("salesQuantity6")
                                 ) AS t(val))
                                ) / (((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                      (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END)) - 1.0)
                            )

                            -- Scenario 8: Medium hits - ≥3 hits (12m)
                            WHEN ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) >= 3
                            THEN GREATEST(
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6" + "salesQuantity7" + "salesQuantity8" + "salesQuantity9" + "salesQuantity10" + "salesQuantity11" +
  "salesQuantity12") -
                                 (SELECT MAX(val) FROM (VALUES
                                     ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                     ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                     ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                 ) AS t(val))
                                ) / 11.0,
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6") -
                                 (SELECT MAX(val) FROM (VALUES
                                     ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                     ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                     ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                 ) AS t(val))
                                ) / 5.0,
                                (("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4") -
                                 (SELECT MAX(val) FROM (VALUES
                                     ("salesQuantity1"), ("salesQuantity2"), ("salesQuantity3"), ("salesQuantity4"),
                                     ("salesQuantity5"), ("salesQuantity6"), ("salesQuantity7"), ("salesQuantity8"),
                                     ("salesQuantity9"), ("salesQuantity10"), ("salesQuantity11"), ("salesQuantity12")
                                 ) AS t(val))
                                ) / 3.0
                            )

                            -- Scenario 9: Low hits - ≥1 hit (12m)
                            WHEN ((CASE WHEN "salesQuantity1" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity2" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity3" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity4" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity5" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity6" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity7" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity8" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity9" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity10" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity11" > 0 THEN 1 ELSE 0 END) +
                                  (CASE WHEN "salesQuantity12" > 0 THEN 1 ELSE 0 END)) >= 1
                            THEN GREATEST(
                                ("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6" + "salesQuantity7" + "salesQuantity8" + "salesQuantity9" + "salesQuantity10" + "salesQuantity11" +
  "salesQuantity12") / 12.0,
                                ("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4" + "salesQuantity5" +
  "salesQuantity6") / 6.0,
                                ("salesQuantity1" + "salesQuantity2" + "salesQuantity3" + "salesQuantity4") / 4.0
                            )

                            ELSE 0
                        END,
                        2
                    ) AS "averageMonthlySales"
                FROM with_product_info d
            )

            --------------------------------------------------------------------
            -- Step 4: Upsert into main table
            --------------------------------------------------------------------
            INSERT INTO public."tSalesY1" (
                company, "salesType", sku, "costOfGoods", sales, margin,
                "salesQuantity12", "salesQuantity11", "salesQuantity10", "salesQuantity9",
                "salesQuantity8", "salesQuantity7", "salesQuantity6", "salesQuantity5",
                "salesQuantity4", "salesQuantity3", "salesQuantity2", "salesQuantity1", "salesQuantity0",
                "salesGroup1", "salesGroup2", "salesGroup3", "salesGroup4", "salesGroup5", "salesGroup6",
                "salesNSW", "salesVIC", "salesQLD", "salesSA", "salesWA", "salesNT", "salesTAS",
                "averageSales12Months", "averageSales9Months", "averageSales6Months", "averageSales3Months",
                "storesSold", "salesHits12Months", "salesHits6Months", "averageMonthlySales", country,
                "createdAt", "updatedAt"
            )
            SELECT
                company, "salesType", sku, "costOfGoods", sales, margin,
                "salesQuantity12", "salesQuantity11", "salesQuantity10", "salesQuantity9",
                "salesQuantity8", "salesQuantity7", "salesQuantity6", "salesQuantity5",
                "salesQuantity4", "salesQuantity3", "salesQuantity2", "salesQuantity1", "salesQuantity0",
                "salesGroup1", "salesGroup2", "salesGroup3", "salesGroup4", "salesGroup5", "salesGroup6",
                "salesNSW", "salesVIC", "salesQLD", "salesSA", "salesWA", "salesNT", "salesTAS",
                "averageSales12Months", "averageSales9Months", "averageSales6Months", "averageSales3Months",
                "storesSold", "salesHits12Months", "salesHits6Months", "averageMonthlySales", country,
                (NOW() AT TIME ZONE 'Australia/Sydney') AS "createdAt", NULL AS "updatedAt"
            FROM computed
            ON CONFLICT (company, "salesType", sku, country)
            DO UPDATE SET
                "costOfGoods" = EXCLUDED."costOfGoods",
                sales = EXCLUDED.sales,
                margin = EXCLUDED.margin,
                "salesQuantity12" = EXCLUDED."salesQuantity12",
                "salesQuantity11" = EXCLUDED."salesQuantity11",
                "salesQuantity10" = EXCLUDED."salesQuantity10",
                "salesQuantity9" = EXCLUDED."salesQuantity9",
                "salesQuantity8" = EXCLUDED."salesQuantity8",
                "salesQuantity7" = EXCLUDED."salesQuantity7",
                "salesQuantity6" = EXCLUDED."salesQuantity6",
                "salesQuantity5" = EXCLUDED."salesQuantity5",
                "salesQuantity4" = EXCLUDED."salesQuantity4",
                "salesQuantity3" = EXCLUDED."salesQuantity3",
                "salesQuantity2" = EXCLUDED."salesQuantity2",
                "salesQuantity1" = EXCLUDED."salesQuantity1",
                "salesQuantity0" = EXCLUDED."salesQuantity0",
                "salesGroup1" = EXCLUDED."salesGroup1",
                "salesGroup2" = EXCLUDED."salesGroup2",
                "salesGroup3" = EXCLUDED."salesGroup3",
                "salesGroup4" = EXCLUDED."salesGroup4",
                "salesGroup5" = EXCLUDED."salesGroup5",
                "salesGroup6" = EXCLUDED."salesGroup6",
                "salesNSW" = EXCLUDED."salesNSW",
                "salesVIC" = EXCLUDED."salesVIC",
                "salesQLD" = EXCLUDED."salesQLD",
                "salesSA" = EXCLUDED."salesSA",
                "salesWA" = EXCLUDED."salesWA",
                "salesNT" = EXCLUDED."salesNT",
                "salesTAS" = EXCLUDED."salesTAS",
                "averageSales12Months" = EXCLUDED."averageSales12Months",
                "averageSales9Months" = EXCLUDED."averageSales9Months",
                "averageSales6Months" = EXCLUDED."averageSales6Months",
                "averageSales3Months" = EXCLUDED."averageSales3Months",
                "storesSold" = EXCLUDED."storesSold",
                "salesHits12Months" = EXCLUDED."salesHits12Months",
                "salesHits6Months" = EXCLUDED."salesHits6Months",
                "averageMonthlySales" = EXCLUDED."averageMonthlySales",
                country = EXCLUDED.country,
                "updatedAt" = (NOW() AT TIME ZONE 'Australia/Sydney');

            GET DIAGNOSTICS v_row_count = ROW_COUNT;
            RAISE NOTICE 'tSalesY1 upsert affected % rows', v_row_count;

            -- Calculate duration and log successful completion
            v_end_time := (NOW() AT TIME ZONE 'Australia/Sydney');
            v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;

            UPDATE execution_log
            SET status = 'SUCCESS',
                end_time = v_end_time,
                duration_ms = v_duration_ms
            WHERE id = v_log_id;

            RAISE NOTICE 'Procedure completed successfully in % ms', v_duration_ms;

        EXCEPTION WHEN OTHERS THEN
            -- Log failure
            v_end_time := (NOW() AT TIME ZONE 'Australia/Sydney');
            v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;

            UPDATE execution_log
            SET status = 'FAILED',
                end_time = v_end_time,
                duration_ms = v_duration_ms
            WHERE id = v_log_id;

            RAISE WARNING 'Error occurred during tSalesY1 processing: %', SQLERRM;
            RAISE;
        END;

    END;

  
$BODY$;
ALTER PROCEDURE public.sp_process_salesy1()
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
