CREATE OR REPLACE PROCEDURE public.sp_inbound_independent()
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
    VALUES ('sp_inbound_independent', 'STARTED', v_start_time)
    RETURNING id INTO v_log_id;
 
    RAISE NOTICE 'Processing independent tables at %', v_timestamp;
 
    --------------------------------------------------------------------------------
    -- STEP 1: tCatalogueSales
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tCatalogueSales...';
 
    WITH deduped AS (
        SELECT
            t.*,
            ROW_NUMBER() OVER (
                PARTITION BY "eventId", sku
                ORDER BY quantity DESC
            ) AS rn
        FROM "tCatalogueSales_temp" t
    )
    INSERT INTO public."tCatalogueSales" AS tgt (
        "eventId", company, sku, page, "salesType",
        quantity, sales, margin, country,
        "createdAt", "updatedAt"
    )
    SELECT
        d."eventId", d.company, d.sku, d.page, d."salesType",
        d.quantity, d.sales, d.margin, d.country,
        (NOW() AT TIME ZONE 'Australia/Sydney'), NULL
    FROM deduped d
    WHERE rn = 1
    ON CONFLICT ("eventId", company, sku, country)
    DO UPDATE SET
        page = EXCLUDED.page,
        "salesType" = EXCLUDED."salesType",
        quantity = EXCLUDED.quantity,
        sales = EXCLUDED.sales,
        margin = EXCLUDED.margin,
        "updatedAt" = (NOW() AT TIME ZONE 'Australia/Sydney');
 
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RAISE NOTICE 'tCatalogueSales: % rows upserted', v_row_count;
 
    --------------------------------------------------------------------------------
    -- STEP 2: tCatalogueSalesHeader
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tCatalogueSalesHeader...';
 
    INSERT INTO public."tCatalogueSalesHeader" AS tgt (
        "eventId", company, "eventDescription", "eventType",
        "startDate", "endDate", "comparisonStartDate", "comparisonEndDate",
        "createdBy", "createdDate", channel, country,
        "createdAt", "updatedAt"
    )
    SELECT DISTINCT ON (t."eventId", t.company, t.country)
        t."eventId",
        'c',
        t."eventDescription",
        t."eventType",
        t."startDate",
        t."endDate",
        t."comparisonStartDate",
        t."comparisonEndDate",
        t."createdBy",
        t."createdDate",
        t.channel,
        t.country,
        (NOW() AT TIME ZONE 'Australia/Sydney'),
        NULL
    FROM public."tCatalogueSalesHeader_temp" t
    ORDER BY t."eventId", t.company, t.country, t."createdDate" DESC
    ON CONFLICT ("eventId", company, country)
    DO UPDATE SET
        "eventDescription"    = EXCLUDED."eventDescription",
        "eventType"           = EXCLUDED."eventType",
        "startDate"           = EXCLUDED."startDate",
        "endDate"             = EXCLUDED."endDate",
        "comparisonStartDate" = EXCLUDED."comparisonStartDate",
        "comparisonEndDate"   = EXCLUDED."comparisonEndDate",
        "createdBy"           = EXCLUDED."createdBy",
        "createdDate"         = EXCLUDED."createdDate",
        channel               = EXCLUDED.channel,
        "updatedAt"           = (NOW() AT TIME ZONE 'Australia/Sydney');
 
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RAISE NOTICE 'tCatalogueSalesHeader: % rows upserted', v_row_count;
 
    --------------------------------------------------------------------------------
    -- STEP 3: tInventory
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tInventory...';
 
    INSERT INTO public."tInventory" (
        company, "locationType", sku,
        "weightedAvgCost", "maxUnits", "maxCount",
        "onHand", "onHandOther", "inTransit", "inTransitOther",
        "onOrder", "physicalInventory", "physicalInventoryValue",
        country, "createdAt", "updatedAt"
    )
    SELECT
        t.company, t."locationType", t.sku,
        t."weightedAvgCost", t."maxUnits", t."maxCount",
        t."onHand", t."onHandOther", t."inTransit", t."inTransitOther",
        t."onOrder", t."physicalInventory", t."physicalInventoryValue",
        t.country,
        (NOW() AT TIME ZONE 'Australia/Sydney'), (NOW() AT TIME ZONE 'Australia/Sydney')
    FROM public."tInventory_temp" t
    ON CONFLICT (company, country, "locationType", sku)
    DO UPDATE SET
        "weightedAvgCost" = EXCLUDED."weightedAvgCost",
        "maxUnits"        = EXCLUDED."maxUnits",
        "maxCount"        = EXCLUDED."maxCount",
        "onHand"          = EXCLUDED."onHand",
        "onHandOther"     = EXCLUDED."onHandOther",
        "inTransit"       = EXCLUDED."inTransit",
        "inTransitOther"  = EXCLUDED."inTransitOther",
        "onOrder"         = EXCLUDED."onOrder",
        "physicalInventory"       = EXCLUDED."physicalInventory",
        "physicalInventoryValue" = EXCLUDED."physicalInventoryValue",
        "updatedAt"       = (NOW() AT TIME ZONE 'Australia/Sydney');
 
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RAISE NOTICE 'tInventory: % rows upserted', v_row_count;
 
    --------------------------------------------------------------------------------
    -- STEP 4: tLocation
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tLocation...';
 
    INSERT INTO public."tLocation" (
        location, "locationName", company, "locationType",
        "associatedLocation", "supplyLocation", "areaName",
        "branchIndicator", "companyName", "companyShortName",
        state, "repcoAreaGroup", zone, "zoneName",
        "stockOnHandLines", "assortmentLines",
        country, "createdAt", "updatedAt"
    )
    SELECT
        t.location, t."locationName", t.company, t."locationType",
        t."associatedLocation", t."supplyLocation", t."areaName",
        t."branchIndicator", t."companyName", t."companyShortName",
        t.state, t."repcoAreaGroup", t.zone, t."zoneName",
        t."stockOnHandLines", t."assortmentLines",
        t.country, (NOW() AT TIME ZONE 'Australia/Sydney'), (NOW() AT TIME ZONE 'Australia/Sydney')
    FROM public."tLocation_temp" t
    ON CONFLICT (location, country)
    DO UPDATE SET
        "locationName"      = EXCLUDED."locationName",
        company             = EXCLUDED.company,
        "locationType"      = EXCLUDED."locationType",
        "associatedLocation"= EXCLUDED."associatedLocation",
        "supplyLocation"    = EXCLUDED."supplyLocation",
        "areaName"          = EXCLUDED."areaName",
        "branchIndicator"   = EXCLUDED."branchIndicator",
        "companyName"       = EXCLUDED."companyName",
        "companyShortName"  = EXCLUDED."companyShortName",
        state               = EXCLUDED.state,
        "repcoAreaGroup"    = EXCLUDED."repcoAreaGroup",
        zone                = EXCLUDED.zone,
        "zoneName"          = EXCLUDED."zoneName",
        "stockOnHandLines"  = EXCLUDED."stockOnHandLines",
        "assortmentLines"   = EXCLUDED."assortmentLines",
        "updatedAt"         = (NOW() AT TIME ZONE 'Australia/Sydney');
 
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RAISE NOTICE 'tLocation: % rows upserted', v_row_count;
 
    --------------------------------------------------------------------------------
    -- STEP 5: tPriceList
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tPriceList...';
 
    DELETE FROM public."tPriceList_temp" t
    USING (
        SELECT
            "company",
            "priceList",
            MIN(ctid) AS keep_ctid
        FROM public."tPriceList_temp"
        GROUP BY "company", "priceList"
        HAVING COUNT(*) > 1
    ) dups
    WHERE t."company" = dups."company"
      AND t."priceList" = dups."priceList"
      AND t.ctid <> dups.keep_ctid;
 
    -- Insert new records or update existing records in main table
    INSERT INTO public."tPriceList" AS main (
        company,
        "priceList",
        "priceListDescription",
        owner,
        active,
        "clearanceType",
        "vehicleInfoRequired",
        "priceListMessageCode",
        "longTermFlag",
        country,
        "createdAt",
        "updatedAt"
    )
    SELECT
        t.company,
        t."priceList",
        t."priceListDescription",
        t.owner,
        t.active,
        t."clearanceType",
        t."vehicleInfoRequired",
        t."priceListMessageCode",
        t."longTermFlag",
        t.country,
        (NOW() AT TIME ZONE 'Australia/Sydney') AS "createdAt",
        NULL AS "updatedAt"
    FROM public."tPriceList_temp" t
    ON CONFLICT (company, "priceList", country)
    DO UPDATE
    SET
        "priceListDescription" = EXCLUDED."priceListDescription",
        owner = EXCLUDED.owner,
        active = EXCLUDED.active,
        "clearanceType" = EXCLUDED."clearanceType",
        "vehicleInfoRequired" = EXCLUDED."vehicleInfoRequired",
        "priceListMessageCode" = EXCLUDED."priceListMessageCode",
        "longTermFlag" = EXCLUDED."longTermFlag",
        country = EXCLUDED.country,
        "updatedAt" = (NOW() AT TIME ZONE 'Australia/Sydney');
 
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RAISE NOTICE 'tPriceList: % rows upserted', v_row_count;
 
    --------------------------------------------------------------------------------
    -- STEP 6: tPriceListDetail
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tPriceListDetail...';
 
    WITH dedup AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY company, country, "priceList", sku
               ORDER BY "startDate" DESC
           ) AS rn
    FROM public."tPriceListDetail_temp"
    WHERE 
        "startDate" <= CURRENT_DATE
        AND "endDate" >= CURRENT_DATE
)
 
INSERT INTO public."tPriceListDetail" (
    company,
    "priceList",
    sku,
    "dateAdded",
    "startDate",
    "endDate",
    "gstInclusiveIndicator",
    "priceListPrice",
    country,
    "createdAt",
    "updatedAt"
)
SELECT
    t.company,
    t."priceList",
    t.sku,
    t."dateAdded",
    t."startDate",
    t."endDate",
    t."gstInclusiveIndicator",
    t."priceListPrice",
    t.country,
    (NOW() AT TIME ZONE 'Australia/Sydney') AS "createdAt",
    (NOW() AT TIME ZONE 'Australia/Sydney') AS "updatedAt"
FROM dedup t
WHERE rn = 1
 
ON CONFLICT (company, country, "priceList", sku)
DO UPDATE SET
    "dateAdded" = EXCLUDED."dateAdded",
    "startDate" = EXCLUDED."startDate",
    "endDate" = EXCLUDED."endDate",
    "gstInclusiveIndicator" = EXCLUDED."gstInclusiveIndicator",
    "priceListPrice" = EXCLUDED."priceListPrice",
    "updatedAt" = (NOW() AT TIME ZONE 'Australia/Sydney');
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
 
    RAISE NOTICE 'tPriceListDetail: % rows upserted', v_row_count;
 
    --------------------------------------------------------------------------------
    -- STEP 7: tPriceProfile (COUNTRY-SPECIFIC)
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tPriceProfile...';
 
    DELETE FROM "tPriceProfile_temp"
    WHERE (country = 'NZ' AND "priceProfile" != 'RET1B')
       OR (country = 'AU' AND "priceProfile" != 'RETLB');
 
    INSERT INTO "tPriceProfile_temp" (
        company, "priceProfile", "startDate", "endDate",
        "priceClass1", "priceClass2",
        "pricePointer", "percentVariation", "percentPriceAdjust", country
    )
    SELECT '85', 'RET1B', '2020-07-20'::DATE, '9999-12-31'::DATE,
           'NA' AS "priceClass1",
           'NA' AS "priceClass2",
           6, 0, 0, 'NZ'
    WHERE NOT EXISTS (
        SELECT 1 FROM "tPriceProfile_temp"
        WHERE company='85' AND "priceProfile"='RET1B' AND country='NZ'
    );
 
    -- Use ROW_NUMBER() to deduplicate
    WITH ranked AS (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY company, "priceProfile",
                                CASE WHEN country='AU' THEN "startDate" ELSE NULL END,
                                CASE WHEN country='AU' THEN "endDate" ELSE NULL END,
                                "priceClass1", "priceClass2", country
                   ORDER BY "startDate" DESC, "endDate" DESC
               ) AS rn
        FROM "tPriceProfile_temp"
    )
    INSERT INTO "tPriceProfile" (
        company, "priceProfile", "startDate", "endDate",
        "priceClass1", "priceClass2",
        "pricePointer", "percentVariation", "percentPriceAdjust", country
    )
    SELECT company, "priceProfile", "startDate", "endDate",
           "priceClass1", "priceClass2",
           "pricePointer", "percentVariation", "percentPriceAdjust", country
    FROM ranked
    WHERE rn = 1
    ON CONFLICT (company, "priceProfile", "priceClass1", "priceClass2", country)
    DO UPDATE SET
        "startDate"         = EXCLUDED."startDate",
        "endDate"           = EXCLUDED."endDate",
        "pricePointer"      = EXCLUDED."pricePointer",
        "percentVariation"  = EXCLUDED."percentVariation",
        "percentPriceAdjust"= EXCLUDED."percentPriceAdjust";
 
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RAISE NOTICE 'tPriceProfile: % rows upserted', v_row_count;
 
    --------------------------------------------------------------------------------
    -- STEP 8: tSalesY2
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tSalesY2...';
 
    WITH dedup AS (
        SELECT t.ctid,
               ROW_NUMBER() OVER (
                   PARTITION BY company, "salesType", sku, country
                   ORDER BY sku
               ) AS rn
        FROM "tSalesY2_temp" t
    )
    DELETE FROM "tSalesY2_temp" t
    USING dedup d
    WHERE t.ctid = d.ctid
      AND d.rn > 1;
 
    INSERT INTO public."tSalesY2" (
        company, "salesType", sku, "costOfGoods",
        sales, margin,
        "salesQuantity24","salesQuantity23","salesQuantity22","salesQuantity21",
        "salesQuantity20","salesQuantity19","salesQuantity18","salesQuantity17",
        "salesQuantity16","salesQuantity15","salesQuantity14","salesQuantity13",
        "salesGroup1","salesGroup2","salesGroup3","salesGroup4","salesGroup5","salesGroup6",
        "salesNSW","salesVIC","salesQLD","salesSA","salesWA","salesNT","salesTAS",
        country, "createdAt", "updatedAt"
    )
    SELECT
        t.company, t."salesType", t.sku, t."costOfGoods",
        t.sales, t.margin,
        t."salesQuantity24", t."salesQuantity23", t."salesQuantity22", t."salesQuantity21",
        t."salesQuantity20", t."salesQuantity19", t."salesQuantity18", t."salesQuantity17",
        t."salesQuantity16", t."salesQuantity15", t."salesQuantity14", t."salesQuantity13",
        t."salesGroup1", t."salesGroup2", t."salesGroup3", t."salesGroup4",
        t."salesGroup5", t."salesGroup6",
        t."salesNSW", t."salesVIC", t."salesQLD", t."salesSA",
        t."salesWA", t."salesNT", t."salesTAS",
        t.country, (NOW() AT TIME ZONE 'Australia/Sydney'), (NOW() AT TIME ZONE 'Australia/Sydney')
    FROM public."tSalesY2_temp" t
    ON CONFLICT (company, "salesType", sku, country)
    DO UPDATE SET
        "costOfGoods" = EXCLUDED."costOfGoods",
        sales         = EXCLUDED.sales,
        margin        = EXCLUDED.margin,
        "salesQuantity24" = EXCLUDED."salesQuantity24",
        "salesQuantity23" = EXCLUDED."salesQuantity23",
        "salesQuantity22" = EXCLUDED."salesQuantity22",
        "salesQuantity21" = EXCLUDED."salesQuantity21",
        "salesQuantity20" = EXCLUDED."salesQuantity20",
        "salesQuantity19" = EXCLUDED."salesQuantity19",
        "salesQuantity18" = EXCLUDED."salesQuantity18",
        "salesQuantity17" = EXCLUDED."salesQuantity17",
        "salesQuantity16" = EXCLUDED."salesQuantity16",
        "salesQuantity15" = EXCLUDED."salesQuantity15",
        "salesQuantity14" = EXCLUDED."salesQuantity14",
        "salesQuantity13" = EXCLUDED."salesQuantity13",
        "salesGroup1" = EXCLUDED."salesGroup1",
        "salesGroup2" = EXCLUDED."salesGroup2",
        "salesGroup3" = EXCLUDED."salesGroup3",
        "salesGroup4" = EXCLUDED."salesGroup4",
        "salesGroup5" = EXCLUDED."salesGroup5",
        "salesGroup6" = EXCLUDED."salesGroup6",
        "salesNSW" = EXCLUDED."salesNSW",
        "salesVIC" = EXCLUDED."salesVIC",
        "salesQLD" = EXCLUDED."salesQLD",
        "salesSA"  = EXCLUDED."salesSA",
        "salesWA"  = EXCLUDED."salesWA",
        "salesNT"  = EXCLUDED."salesNT",
        "salesTAS" = EXCLUDED."salesTAS",
        "updatedAt" = (NOW() AT TIME ZONE 'Australia/Sydney');
 
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RAISE NOTICE 'tSalesY2: % rows upserted', v_row_count;
 
    --------------------------------------------------------------------------------
    -- STEP 9: tStockCover
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tStockCover...';
 
    INSERT INTO public."tStockCover" (
        company, sku,
        "stockOnHandGroup1","stockOnHandGroup2","stockOnHandGroup3","stockOnHandGroup4","stockOnHandGroup5",
        "stockCountGroup1","stockCountGroup2","stockCountGroup3","stockCountGroup4","stockCountGroup5",
        "stockCount1Group1","stockCount2Group1","stockCount35Group1","stockCount610Group1","stockCount11Group1",
        "stockCount1Group2","stockCount2Group2","stockCount35Group2","stockCount610Group2","stockCount11Group2",
        "stockCount1Group3","stockCount2Group3","stockCount35Group3","stockCount610Group3","stockCount11Group3",
        "stockCount1Group4","stockCount2Group4","stockCount35Group4","stockCount610Group4","stockCount11Group4",
        "stockCount1Group5","stockCount2Group5","stockCount35Group5","stockCount610Group5","stockCount11Group5",
        country, "createdAt","updatedAt"
    )
    SELECT
        t.company, t.sku,
        t."stockOnHandGroup1",t."stockOnHandGroup2",t."stockOnHandGroup3",t."stockOnHandGroup4",t."stockOnHandGroup5",
        t."stockCountGroup1",t."stockCountGroup2",t."stockCountGroup3",t."stockCountGroup4",t."stockCountGroup5",
        t."stockCount1Group1",t."stockCount2Group1",t."stockCount35Group1",t."stockCount610Group1",t."stockCount11Group1",
        t."stockCount1Group2",t."stockCount2Group2",t."stockCount35Group2",t."stockCount610Group2",t."stockCount11Group2",
        t."stockCount1Group3",t."stockCount2Group3",t."stockCount35Group3",t."stockCount610Group3",t."stockCount11Group3",
        t."stockCount1Group4",t."stockCount2Group4",t."stockCount35Group4",t."stockCount610Group4",t."stockCount11Group4",
        t."stockCount1Group5",t."stockCount2Group5",t."stockCount35Group5",t."stockCount610Group5",t."stockCount11Group5",
        t.country, (NOW() AT TIME ZONE 'Australia/Sydney'), (NOW() AT TIME ZONE 'Australia/Sydney')
    FROM public."tStockCover_temp" t
    ON CONFLICT (company, sku, country)
    DO UPDATE SET
        "stockOnHandGroup1"=EXCLUDED."stockOnHandGroup1",
        "stockOnHandGroup2"=EXCLUDED."stockOnHandGroup2",
        "stockOnHandGroup3"=EXCLUDED."stockOnHandGroup3",
        "stockOnHandGroup4"=EXCLUDED."stockOnHandGroup4",
        "stockOnHandGroup5"=EXCLUDED."stockOnHandGroup5",
        "stockCountGroup1"=EXCLUDED."stockCountGroup1",
        "stockCountGroup2"=EXCLUDED."stockCountGroup2",
        "stockCountGroup3"=EXCLUDED."stockCountGroup3",
        "stockCountGroup4"=EXCLUDED."stockCountGroup4",
        "stockCountGroup5"=EXCLUDED."stockCountGroup5",
        "stockCount1Group1"=EXCLUDED."stockCount1Group1",
        "stockCount2Group1"=EXCLUDED."stockCount2Group1",
        "stockCount35Group1"=EXCLUDED."stockCount35Group1",
        "stockCount610Group1"=EXCLUDED."stockCount610Group1",
        "stockCount11Group1"=EXCLUDED."stockCount11Group1",
        "stockCount1Group2"=EXCLUDED."stockCount1Group2",
        "stockCount2Group2"=EXCLUDED."stockCount2Group2",
        "stockCount35Group2"=EXCLUDED."stockCount35Group2",
        "stockCount610Group2"=EXCLUDED."stockCount610Group2",
        "stockCount11Group2"=EXCLUDED."stockCount11Group2",
        "stockCount1Group3"=EXCLUDED."stockCount1Group3",
        "stockCount2Group3"=EXCLUDED."stockCount2Group3",
        "stockCount35Group3"=EXCLUDED."stockCount35Group3",
        "stockCount610Group3"=EXCLUDED."stockCount610Group3",
        "stockCount11Group3"=EXCLUDED."stockCount11Group3",
        "stockCount1Group4"=EXCLUDED."stockCount1Group4",
        "stockCount2Group4"=EXCLUDED."stockCount2Group4",
        "stockCount35Group4"=EXCLUDED."stockCount35Group4",
        "stockCount610Group4"=EXCLUDED."stockCount610Group4",
        "stockCount11Group4"=EXCLUDED."stockCount11Group4",
        "stockCount1Group5"=EXCLUDED."stockCount1Group5",
        "stockCount2Group5"=EXCLUDED."stockCount2Group5",
        "stockCount35Group5"=EXCLUDED."stockCount35Group5",
        "stockCount610Group5"=EXCLUDED."stockCount610Group5",
        "stockCount11Group5"=EXCLUDED."stockCount11Group5",
        "updatedAt"=(NOW() AT TIME ZONE 'Australia/Sydney');
 
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RAISE NOTICE 'tStockCover: % rows upserted', v_row_count;
 
    --------------------------------------------------------------------------------
    -- STEP 10: tCompanyItem
    --------------------------------------------------------------------------------
    RAISE NOTICE 'Processing tCompanyItem...';
 
    INSERT INTO public."tCompanyItem" (
        company, sku, country, "createdAt", "updatedAt"
    )
    SELECT DISTINCT company, sku, country, (NOW() AT TIME ZONE 'Australia/Sydney'), (NOW() AT TIME ZONE 'Australia/Sydney')
    FROM public."tCompanyItem_temp"
    ON CONFLICT (company, sku, country)
    DO NOTHING;
 
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    RAISE NOTICE 'tCompanyItem: % rows upserted', v_row_count;
 
    -- Calculate duration and log successful completion
    v_end_time := (NOW() AT TIME ZONE 'Australia/Sydney');
    v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
 
    UPDATE execution_log
    SET status = 'SUCCESS',
        end_time = v_end_time,
        duration_ms = v_duration_ms
    WHERE id = v_log_id;
 
    RAISE NOTICE 'Procedure completed successfully in % ms', v_duration_ms;
 
EXCEPTION
    WHEN OTHERS THEN
        -- Log failure
        v_end_time := (NOW() AT TIME ZONE 'Australia/Sydney');
        v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
 
        UPDATE execution_log
        SET status = 'FAILED',
            end_time = v_end_time,
            duration_ms = v_duration_ms
        WHERE id = v_log_id;
 
        RAISE EXCEPTION 'Error in sp_inbound_independent: % - %', SQLERRM, SQLSTATE;
END;
$BODY$;
ALTER PROCEDURE public.sp_inbound_independent()
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
