CREATE OR REPLACE PROCEDURE public.sp_tblprod_dpdt()
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
    VALUES ('sp_tblprod_dpdt', 'STARTED', v_start_time)
    RETURNING id INTO v_log_id;


    RAISE NOTICE 'Processing independent tables at %', v_timestamp;


    BEGIN
        --------------------------------------------------------------------
        -- 1. DEDUP for tIicePartDesc_temp
        --------------------------------------------------------------------
        DELETE FROM public."tIicePartDesc_temp" t
        USING (
            SELECT "partId", MIN(ctid) AS keep_ctid
            FROM public."tIicePartDesc_temp"
            GROUP BY "partId"
            HAVING COUNT(*) > 1
        ) dups
        WHERE t."partId" = dups."partId"
          AND t.ctid <> dups.keep_ctid;


        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        RAISE NOTICE 'tIicePartDesc_temp dedup removed % rows', v_row_count;


        --------------------------------------------------------------------
        -- 2. UPSERT tIicePartDesc
        --------------------------------------------------------------------
        INSERT INTO public."tIicePartDesc" AS main (
            "partId", country, sku,
            "webPartDescription",
            "thumbnailImageName",
            "baseImageName",
            "marketingCopy",
            "createdAt", "updatedAt"
        )
        SELECT
            t."partId", t.country, t.sku,
            t."webPartDescription",
            t."thumbnailImageName",
            t."baseImageName",
            t."marketingCopy",
            (NOW() AT TIME ZONE 'Australia/Sydney'), NULL
        FROM public."tIicePartDesc_temp" t
        ON CONFLICT ("partId", country)
        DO UPDATE SET
            sku = EXCLUDED.sku,
            "webPartDescription" = EXCLUDED."webPartDescription",
            "thumbnailImageName" = EXCLUDED."thumbnailImageName",
            "baseImageName" = EXCLUDED."baseImageName",
            "marketingCopy" = EXCLUDED."marketingCopy",
            "updatedAt" = (NOW() AT TIME ZONE 'Australia/Sydney');


        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        RAISE NOTICE 'tIicePartDesc upsert affected % rows', v_row_count;


        --------------------------------------------------------------------
        -- 3. UPSERT NationalAverageCost
        --------------------------------------------------------------------
        INSERT INTO public."tNationalAverageCost" (
            country, sku, company,
            "effectiveFromDate", "effectiveToDate",
            "nationalAverageCost", "trueLandedCost",
            "generalProvision", "importVariant",
            "currencyGain", rebate, "internalLoading",
            "createdAt", "updatedAt"
        )
        SELECT
            t.country, t.sku, t.company,
            t."effectiveFromDate", t."effectiveToDate",
            t."nationalAverageCost", t."trueLandedCost",
            t."generalProvision", t."importVariant",
            t."currencyGain", t.rebate, t."internalLoading",
            (NOW() AT TIME ZONE 'Australia/Sydney'), (NOW() AT TIME ZONE 'Australia/Sydney')
        FROM public."tNationalAverageCost_temp" t
        ON CONFLICT (sku, country)
        DO UPDATE SET
            company             = EXCLUDED.company,
            "effectiveFromDate" = EXCLUDED."effectiveFromDate",
            "effectiveToDate"   = EXCLUDED."effectiveToDate",
            "nationalAverageCost" = EXCLUDED."nationalAverageCost",
            "trueLandedCost"    = EXCLUDED."trueLandedCost",
            "generalProvision"  = EXCLUDED."generalProvision",
            "importVariant"     = EXCLUDED."importVariant",
            "currencyGain"      = EXCLUDED."currencyGain",
            rebate              = EXCLUDED.rebate,
            "internalLoading"   = EXCLUDED."internalLoading",
            "updatedAt"         = (NOW() AT TIME ZONE 'Australia/Sydney');


        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        RAISE NOTICE 'NationalAverageCost upsert affected % rows', v_row_count;


        --------------------------------------------------------------------
        -- 4. UPSERT Supplier
        --------------------------------------------------------------------
        INSERT INTO public."tSupplier" (
            "supplierId", country, "supplierName",
            "importIndicator", "createdDate", "termsCode",
            "d365SupplierId", "d365SupplierType",
            "createdAt", "updatedAt"
        )
        SELECT
            t."supplierId", t.country, t."supplierName",
            t."importIndicator", t."createdDate", t."termsCode",
            t."d365SupplierId", t."d365SupplierType",
            (NOW() AT TIME ZONE 'Australia/Sydney'), (NOW() AT TIME ZONE 'Australia/Sydney')
        FROM public."tSupplier_temp" t
        WHERE COALESCE(TRIM(LOWER(t."supplierId")), '') NOT IN ('unknown', '*unknown*', '')
        ON CONFLICT ("supplierId", country)
        DO UPDATE SET
            "supplierName"     = EXCLUDED."supplierName",
            "importIndicator"  = EXCLUDED."importIndicator",
            "createdDate"      = EXCLUDED."createdDate",
            "termsCode"        = EXCLUDED."termsCode",
            "d365SupplierId"   = EXCLUDED."d365SupplierId",
            "d365SupplierType" = EXCLUDED."d365SupplierType",
            "updatedAt"        = (NOW() AT TIME ZONE 'Australia/Sydney');


        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        RAISE NOTICE 'Supplier upsert affected % rows', v_row_count;


        --------------------------------------------------------------------
        -- 5. UPSERT VendorItemDetail
        --------------------------------------------------------------------
        INSERT INTO public."tVendorItemDetail" (
            "distributionCenter", "supplierId", sku,
            "latestEffectiveCost", "baseUnitOfMeasure",
            "purchaseUnitOfMeasure", "conversionFactor",
            "deliveryNoteRequired", "leadTime",
            "minimumOrderQuantity", "orderMultiple",
            "d365SupplierId", "d365SupplierType",
            country, "createdAt", "updatedAt"
        )
        SELECT
            t."distributionCenter", t."supplierId", t.sku,
            t."latestEffectiveCost", t."baseUnitOfMeasure",
            t."purchaseUnitOfMeasure", t."conversionFactor",
            t."deliveryNoteRequired", t."leadTime",
            t."minimumOrderQuantity", t."orderMultiple",
            t."d365SupplierId", t."d365SupplierType",
            t.country, (NOW() AT TIME ZONE 'Australia/Sydney'), (NOW() AT TIME ZONE 'Australia/Sydney')
        FROM public."tVendorItemDetail_temp" t
        ON CONFLICT ("distributionCenter","supplierId",sku,country)
        DO UPDATE SET
            "latestEffectiveCost" = EXCLUDED."latestEffectiveCost",
            "baseUnitOfMeasure" = EXCLUDED."baseUnitOfMeasure",
            "purchaseUnitOfMeasure" = EXCLUDED."purchaseUnitOfMeasure",
            "conversionFactor" = EXCLUDED."conversionFactor",
            "deliveryNoteRequired" = EXCLUDED."deliveryNoteRequired",
            "leadTime" = EXCLUDED."leadTime",
            "minimumOrderQuantity" = EXCLUDED."minimumOrderQuantity",
            "orderMultiple" = EXCLUDED."orderMultiple",
            "d365SupplierId" = EXCLUDED."d365SupplierId",
            "d365SupplierType" = EXCLUDED."d365SupplierType",
            "updatedAt" = (NOW() AT TIME ZONE 'Australia/Sydney');


        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        RAISE NOTICE 'VendorItemDetail upsert affected % rows', v_row_count;


        --------------------------------------------------------------------
        -- 6. UPSERT ItemClass
        --------------------------------------------------------------------
        INSERT INTO public."tItemClass" (
            "itemClass1","itemClass2","itemClass3","itemClass4",
            country,"merchandisingGroup","categoryManager",
            "categoryAssistant","itemClass1Description",
            "itemClass2Description","itemClass3Description",
            "itemClass4Description","createdAt","updatedAt"
        )
        SELECT
            t."itemClass1",t."itemClass2",t."itemClass3",t."itemClass4",
            t.country,t."merchandisingGroup",t."categoryManager",
            t."categoryAssistant",t."itemClass1Description",
            t."itemClass2Description",t."itemClass3Description",
            t."itemClass4Description",(NOW() AT TIME ZONE 'Australia/Sydney'),(NOW() AT TIME ZONE 'Australia/Sydney')
        FROM public."tItemClass_temp" t
        ON CONFLICT ("itemClass1","itemClass2","itemClass3","itemClass4",country)
        DO UPDATE SET
            "merchandisingGroup" = EXCLUDED."merchandisingGroup",
            "categoryManager" = EXCLUDED."categoryManager",
            "categoryAssistant" = EXCLUDED."categoryAssistant",
            "itemClass1Description" = EXCLUDED."itemClass1Description",
            "itemClass2Description" = EXCLUDED."itemClass2Description",
            "itemClass3Description" = EXCLUDED."itemClass3Description",
            "itemClass4Description" = EXCLUDED."itemClass4Description",
            "updatedAt" = (NOW() AT TIME ZONE 'Australia/Sydney');


        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        RAISE NOTICE 'ItemClass upsert affected % rows', v_row_count;


        --------------------------------------------------------------------
        -- 7. UPSERT ItemLoadings
        --------------------------------------------------------------------
        INSERT INTO public."tItemLoadings" AS main (
            "supplierId", sku, "itemClass", country,
            "parameterType","loadingLevel","dateAdded","startDate",
            "percentageLoading","dollarLoading","createdAt","updatedAt"
        )
        SELECT
            t."supplierId",t.sku,t."itemClass",t.country,
            t."parameterType",t."loadingLevel",t."dateAdded",
            t."startDate",t."percentageLoading",t."dollarLoading",
            (NOW() AT TIME ZONE 'Australia/Sydney'),NULL
        FROM public."tItemLoadings_temp" t
        ON CONFLICT ("supplierId",sku,"itemClass",country)
        DO UPDATE SET
            "parameterType" = EXCLUDED."parameterType",
            "loadingLevel" = EXCLUDED."loadingLevel",
            "dateAdded" = EXCLUDED."dateAdded",
            "startDate" = EXCLUDED."startDate",
            "percentageLoading" = EXCLUDED."percentageLoading",
            "dollarLoading" = EXCLUDED."dollarLoading",
            "updatedAt" = (NOW() AT TIME ZONE 'Australia/Sydney');


        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        RAISE NOTICE 'ItemLoadings upsert affected % rows', v_row_count;


        --------------------------------------------------------------------
        -- 8. UPSERT ProductSupplierCost
        --------------------------------------------------------------------
        INSERT INTO public."tProductSupplierCost" (
            country,
            "supplierId",
            sku,
            "costLocation",
            "purchaseUOM",
            "startDate",
            "endDate",
            "rapSellFromDate",
            "sellTrigger",
            "packageType",
            "conversionFactor",
            "fromQuantity",
            "toQuantity",
            "baseCost",
            "discountAmount",
            "purchaseUomCost",
            "costPerEach",
            "createdAt",
            "updatedAt"
        )
        SELECT DISTINCT ON ("supplierId", sku)
            country,
            "supplierId",
            sku,
            "costLocation",
            "purchaseUOM",
            "startDate",
            "endDate",
            "rapSellFromDate",
            "sellTrigger",
            "packageType",
            "conversionFactor",
            "fromQuantity",
            "toQuantity",
            "baseCost",
            "discountAmount",
            "purchaseUomCost",
            "costPerEach",
            (NOW() AT TIME ZONE 'Australia/Sydney') AS "createdAt",
            NULL AS "updatedAt"
        FROM "tProductSupplierCost_temp"
        ORDER BY
            "supplierId",
            sku,
            CASE WHEN "sellTrigger" = 'Y' THEN 0 ELSE 1 END,
            "startDate" DESC,
            "endDate" DESC
        ON CONFLICT ("supplierId", sku)
        DO UPDATE SET
            country            = EXCLUDED.country,
            "costLocation"     = EXCLUDED."costLocation",
            "purchaseUOM"      = EXCLUDED."purchaseUOM",
            "startDate"        = EXCLUDED."startDate",
            "endDate"          = EXCLUDED."endDate",
            "rapSellFromDate"  = EXCLUDED."rapSellFromDate",
            "sellTrigger"      = EXCLUDED."sellTrigger",
            "packageType"      = EXCLUDED."packageType",
            "conversionFactor" = EXCLUDED."conversionFactor",
            "fromQuantity"     = EXCLUDED."fromQuantity",
            "toQuantity"       = EXCLUDED."toQuantity",
            "baseCost"         = EXCLUDED."baseCost",
            "discountAmount"   = EXCLUDED."discountAmount",
            "purchaseUomCost"  = EXCLUDED."purchaseUomCost",
            "costPerEach"      = EXCLUDED."costPerEach",
            "updatedAt"        = (NOW() AT TIME ZONE 'Australia/Sydney');


        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        RAISE NOTICE 'ProductSupplierCost upsert affected % rows', v_row_count;


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


        RAISE WARNING 'Error occurred: %', SQLERRM;
        RAISE;
    END;


END;
$BODY$;
ALTER PROCEDURE public.sp_tblprod_dpdt()
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
