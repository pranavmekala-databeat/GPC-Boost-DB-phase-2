CREATE OR REPLACE PROCEDURE public.sp_update_event_offer_detailspctstd()
LANGUAGE plpgsql
AS $BODY$
DECLARE
    v_start_time timestamptz;
    v_end_time   timestamptz;
    v_log_id     bigint;
    v_job_name   text := 'sp_update_event_offer_detailsPCTSTD';
BEGIN
    -- Run in Australia/Sydney time
    SET LOCAL TIME ZONE 'Australia/Sydney';

    -- Start log
    v_start_time := clock_timestamp();

    INSERT INTO execution_log (job_name, status, start_time)
    VALUES (v_job_name, 'STARTED', v_start_time)
    RETURNING id INTO v_log_id;

-- ===================================================================================================
-- UPDATE tEventOfferDetail For STD Range Price
--===============================================================================================================

--STDRangePrice
WITH updateEventOfferDtlForSTDRangePrice AS (
        SELECT
            eod."sku",
            eod."offerNo",
            eod."offerId",
            eoh."offerType",
			eoh."OfferTypeId",
            p."clearance",
            rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5",
            (COALESCE(s."averageMonthlySales", 0) / 30.0) *
            ((COALESCE(eoh."endDate", eh."endDate") - COALESCE(eoh."startDate", eh."startDate")) + 1) AS calc_units,
            config."configvalue"->>'channel' AS "salesType",
            eod."gst" AS gst_value,
            ppr."exchangeRatePrice",
            ppr."priceControlPlan",
            ppr."pricePoint2",
            p."vendorCostPerEach",
            p."nationalAvgCost",
			eoh."spacePurchase",
            eoh."incrementalPercentage",
			eoh."advertisedPriceGst",			
			eod."everydayUnits",
			eod."categoryforecast",
			eod."isCategoryForecastLocked",
            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") = 'STORE' THEN inv."onHand" END), 0) AS sohStore,
            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") <> 'STORE' THEN inv."onHand" END), 0) AS sohDc

        FROM "tEventOfferDetail" eod
        INNER JOIN "tEventOffer" eoh
            ON eod."offerId" = eoh."offerId"
           AND eod."offerNo" = eoh."offerNumber"
        INNER JOIN "tEvent" eh
            ON eh."eventId" = eoh."eventId"
			 INNER JOIN "tProducts" p
            ON p."sku" = eod."sku"
        INNER JOIN "tPriceProductRules" ppr
            ON ppr."sku" = eod."sku"
AND ppr."company" = eh."company"
 and ppr."supplierId"=p."supplierId"
            and ppr."startDate"<=CURRENT_DATE and  ppr."endDate">=CURRENT_DATE

       
        INNER JOIN "tConfig" config
            ON config."configkey" = eh."channel"
           AND config."country" = eh."country"
           AND config."configtype" = 'SalesType'
         LEFT JOIN "tInventory" inv
            ON inv."sku" = eod."sku"
			AND inv."company" IN (eh."company",'12','52')
		 LEFT JOIN "tSalesY1" s
            ON s."sku" = eod."sku"
           AND s."company" = eh."company"
		   AND s."salesType" = config."configvalue" ->> 'channel'
        LEFT JOIN "tRegionalAreaGroupAllocation" rag
             on rag."allocationGroup"='DEFAULT'
			 AND rag."country" = eh."country"
		WHERE eoh."OfferTypeId" IN (14)
		AND UPPER(eh."status") <> 'COMPLETED'
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId",eoh."offerType", 
            eoh."offerId", eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            config."configvalue",
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost", p."clearance",
            eoh."incrementalPercentage", rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5", 
			 eoh."spacePurchase",
			eoh."advertisedPriceGst",
			s."averageMonthlySales",			
			eod."everydayUnits",
			eod."categoryforecast",
			eoh."OfferTypeId",
			eod."isCategoryForecastLocked",
			eod."gst"
    ),

    calculationsForEventOfferDtlSTDRangePrice AS (
        SELECT
            d.*,
            ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            ),2) AS new_everydayPriceGst,
			CASE 
			WHEN d."isCategoryForecastLocked" = FALSE 
			THEN CAST(ROUND((d."incrementalPercentage"::numeric / 100)* ROUND(d.calc_units)::numeric) AS integer)
			ELSE d."categoryforecast" END as categoryFcst,
			CASE WHEN d."clearance" = 'Y' THEN ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            ),2)
			ELSE ROUND(d."advertisedPriceGst",2) END AS new_advertisedPriceGst,
			CASE WHEN d."clearance" = 'Y' THEN ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            )/(1+ COALESCE(d.gst_value, 0)),2)
			ELSE ROUND((d."advertisedPriceGst")/(1+ COALESCE(d.gst_value, 0)),2) END AS new_advertisedPrice,
			ROUND(d."nationalAvgCost",2) as natAvgCost
        FROM updateEventOfferDtlForSTDRangePrice d
    )
    UPDATE "tEventOfferDetail" e
    SET
        "everydayUnits" = ROUND(c.calc_units),
        "everydayPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGst" = c.new_everydayPriceGst,
        "everydayPriceGstSys" = c.new_everydayPriceGst,
		"advertisedPriceGst" = c.new_advertisedPriceGst,
		"advertisedPrice" = c.new_advertisedPrice,
		"calculatedSaveValue"= Round(c.new_everydayPriceGst-c.new_advertisedPriceGst,2),
		"calculatedSavePercentage" = CASE 
    WHEN c.new_everydayPriceGst > 0 THEN ROUND(((c.new_everydayPriceGst - c.new_advertisedPriceGst) / c.new_everydayPriceGst)* 100, 2)
    ELSE 0 
END,
		"categoryforecast" = c.categoryFcst,
        "forecastCost"=Round(ROUND(COALESCE(c."vendorCostPerEach",0),2)*c.categoryFcst,2),
        "forecastSales"=Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2),
		"incrementalForecast"=c.categoryFcst-ROUND(c.calc_units),
        "nationalAverageCost" = COALESCE(c.natAvgCost, 0),
		"clearanceIndicator" = CASE WHEN c."clearance" IS NULL OR TRIM(c."clearance") = '' THEN 'N' ELSE c."clearance" END,
         "forecastTradeMargin$" = ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2),
        "stockOnHandStore" = c.sohStore,
        "stockOnHandDC"    = c.sohDc,
        "LatestEffectiveCost" = ROUND(ROUND(COALESCE(c."vendorCostPerEach",0),2),2),
        "categoryCost"        = COALESCE(c.natAvgCost, 0),
      
        "everydayExtendedUnitCost"  = ROUND(c.calc_units) * COALESCE(c.natAvgCost, 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units )* c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units )* COALESCE(c.new_advertisedPriceGst, 0),
        "everydayCost" = COALESCE(c.natAvgCost, 0),
        "incrementalSales"=Round(Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2) - (ROUND(c.calc_units)*c.new_everydayPriceGst),2),
        "incrementalTrade$" =  ROUND( ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2) - ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2)-ROUND(COALESCE(c."vendorCostPerEach",0),2) )*ROUND(c.calc_units),2), 2),
        "forecastTradeMargin%" = CASE 
        WHEN Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2) > 0
        THEN             
               ROUND(((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst) / (c.categoryFcst * c.new_advertisedPrice) * 100, 2)

        ELSE 0
		END,
		"totalTieUp" = 
        (COALESCE(e."group0Quantity",0) * COALESCE(c."G0",0)) +
        (COALESCE(e."group1Quantity",0) * COALESCE(c."G1",0)) +
        (COALESCE(e."group2Quantity",0) * COALESCE(c."G2",0)) +
        (COALESCE(e."group3Quantity",0) * COALESCE(c."G3",0)) +
        (COALESCE(e."group4Quantity",0) * COALESCE(c."G4",0)) +
        (COALESCE(e."group5Quantity",0) * COALESCE(c."G5",0)),
    "tieUpCost" = ROUND(
        ((COALESCE(e."group0Quantity",0) * COALESCE(c."G0",0)) +
         (COALESCE(e."group1Quantity",0) * COALESCE(c."G1",0)) +
         (COALESCE(e."group2Quantity",0) * COALESCE(c."G2",0)) +
         (COALESCE(e."group3Quantity",0) * COALESCE(c."G3",0)) +
         (COALESCE(e."group4Quantity",0) * COALESCE(c."G4",0)) +
         (COALESCE(e."group5Quantity",0) * COALESCE(c."G5",0)))
         * ROUND(COALESCE(c."vendorCostPerEach",0),2),
    2)
    FROM calculationsForEventOfferDtlSTDRangePrice c
    WHERE e."sku" = c."sku"
      AND e."offerNo" = c."offerNo"
      AND e."offerId" = c."offerId"
      AND c."OfferTypeId" IN (14);

-- ===================================================================================================
-- UPDATE tEventOfferDetail For PCT OFF RANGE
--===============================================================================================================

--updateEventOfferDtlForPCTOffRange
WITH updateEventOfferDtlForPCTOffRange AS (
        SELECT
            eod."sku",
            eod."offerNo",
            eod."offerId",
            eoh."offerType",
			eoh."OfferTypeId",
            p."clearance",
			eoh."savePercent",
            rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5",
            (COALESCE(s."averageMonthlySales", 0) / 30.0) *
            ((COALESCE(eoh."endDate", eh."endDate") - COALESCE(eoh."startDate", eh."startDate")) + 1) AS calc_units,
            config."configvalue"->>'channel' AS "salesType",
            eod."gst" AS gst_value,
            ppr."exchangeRatePrice",
            ppr."priceControlPlan",
            ppr."pricePoint2",
            p."vendorCostPerEach",
            p."nationalAvgCost",
            eoh."incrementalPercentage",
			eod."everydayUnits",
			eod."categoryforecast",
			eoh."spacePurchase",
			eod."isCategoryForecastLocked",
            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") = 'STORE' THEN inv."onHand" END), 0) AS sohStore,
            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") <> 'STORE' THEN inv."onHand" END), 0) AS sohDc

        FROM "tEventOfferDetail" eod
        INNER JOIN "tEventOffer" eoh
            ON eod."offerId" = eoh."offerId"
           AND eod."offerNo" = eoh."offerNumber"
        INNER JOIN "tEvent" eh
            ON eh."eventId" = eoh."eventId"
			INNER JOIN "tProducts" p
            ON p."sku" = eod."sku"
        INNER JOIN "tPriceProductRules" ppr
            ON ppr."sku" = eod."sku"
AND ppr."company" = eh."company"
 and ppr."supplierId"=p."supplierId"
            and ppr."startDate"<=CURRENT_DATE and  ppr."endDate">=CURRENT_DATE

        
        INNER JOIN "tConfig" config
            ON config."configkey" = eh."channel"
           AND config."country" = eh."country"
           AND config."configtype" = 'SalesType'
        LEFT JOIN "tInventory" inv
            ON inv."sku" = eod."sku"
			AND inv."company" IN (eh."company",'12','52')
		 LEFT JOIN "tSalesY1" s
            ON s."sku" = eod."sku"
           AND s."company" = eh."company"
		   AND s."salesType" = config."configvalue" ->> 'channel'
        LEFT JOIN "tRegionalAreaGroupAllocation" rag
             on rag."allocationGroup"='DEFAULT'
			 AND rag."country" = eh."country"
		WHERE eoh."OfferTypeId" IN (6)
		AND UPPER(eh."status") <> 'COMPLETED'
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId",eoh."offerType", 
            eoh."offerId",  eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            config."configvalue",
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost", p."clearance",
            eoh."incrementalPercentage", rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5", 
			 eoh."spacePurchase",
			 eoh."savePercent",
			 eod."everydayUnits",
			 s."averageMonthlySales",
			 eod."categoryforecast",
			 eoh."OfferTypeId",
			 eod."isCategoryForecastLocked",
			 eod."gst"
    ),

    calculationsForEventOfferDtlPCTOffRange AS (
        SELECT
            d.*,
            ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            ),2) AS new_everydayPriceGst,
			CASE 
			WHEN d."isCategoryForecastLocked" = FALSE 
			THEN CAST(ROUND((d."incrementalPercentage"::numeric / 100)* ROUND(d.calc_units)::numeric) AS integer)
			ELSE d."categoryforecast" END AS categoryFcst,
			CASE WHEN d."clearance" = 'Y' THEN ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            ),2)
			ELSE ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            ) - (COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            )*d."savePercent"/100),2) END AS new_advertisedPriceGst,
			CASE WHEN d."clearance" = 'Y' THEN ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            )/(1+ COALESCE(d.gst_value, 0)),2)
			ELSE  ROUND((COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            ) - (COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            )*d."savePercent"/100))/(1+ COALESCE(d.gst_value, 0)),2) END AS new_advertisedPrice
			
        FROM updateEventOfferDtlForPCTOffRange d
    )
    UPDATE "tEventOfferDetail" e
    SET
        "everydayUnits" = ROUND(c.calc_units),
        "everydayPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGst" = c.new_everydayPriceGst,
        "everydayPriceGstSys" = c.new_everydayPriceGst,
		"advertisedPriceGst"= c.new_advertisedPriceGst,
		"advertisedPrice"= c.new_advertisedPrice,
"calculatedSaveValue"= Round(e."everydayPriceGst"-c.new_advertisedPriceGst,2),
		"calculatedSavePercentage" = CASE 
    WHEN c.new_everydayPriceGst > 0 THEN ROUND(((c.new_everydayPriceGst - c.new_advertisedPriceGst) / c.new_everydayPriceGst)* 100, 2)
    ELSE 0 
END,
"clearanceIndicator" = CASE WHEN c."clearance" IS NULL OR TRIM(c."clearance") = '' THEN 'N' ELSE c."clearance" END,
		"categoryforecast" = c.categoryFcst,
        "forecastCost"=Round(ROUND(COALESCE(c."vendorCostPerEach",0),2)*c.categoryFcst,2),
        "forecastSales"=Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2),
		"incrementalForecast"=c.categoryFcst-ROUND(c.calc_units),
        "nationalAverageCost" = COALESCE(c."nationalAvgCost", 0),
         "forecastTradeMargin$" = ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2),
        "stockOnHandStore" = c.sohStore,
        "stockOnHandDC"    = c.sohDc,
        "LatestEffectiveCost" = ROUND(ROUND(COALESCE(c."vendorCostPerEach",0),2),2),
        "categoryCost"        = COALESCE(c."nationalAvgCost", 0),
      
        "everydayExtendedUnitCost"  = ROUND(c.calc_units )* COALESCE(c."nationalAvgCost", 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units )* c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units )* COALESCE(c.new_advertisedPriceGst, 0),
        "everydayCost" = COALESCE(c."nationalAvgCost", 0),
        "incrementalSales"=Round(Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2) - (ROUND(c.calc_units)*c.new_everydayPriceGst),2),
        "incrementalTrade$" =  ROUND( ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2) - ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2)-ROUND(COALESCE(c."vendorCostPerEach",0),2) )*ROUND(c.calc_units),2), 2),
        "forecastTradeMargin%" = CASE 
        WHEN Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2) > 0
        THEN             
               ROUND(((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) *c.categoryFcst) / (c.categoryFcst * c.new_advertisedPrice) * 100, 2)

        ELSE 0
		END,
		"totalTieUp" = 
        (COALESCE(e."group0Quantity",0) * COALESCE(c."G0",0)) +
        (COALESCE(e."group1Quantity",0) * COALESCE(c."G1",0)) +
        (COALESCE(e."group2Quantity",0) * COALESCE(c."G2",0)) +
        (COALESCE(e."group3Quantity",0) * COALESCE(c."G3",0)) +
        (COALESCE(e."group4Quantity",0) * COALESCE(c."G4",0)) +
        (COALESCE(e."group5Quantity",0) * COALESCE(c."G5",0)),
    "tieUpCost" = ROUND(
        ((COALESCE(e."group0Quantity",0) * COALESCE(c."G0",0)) +
         (COALESCE(e."group1Quantity",0) * COALESCE(c."G1",0)) +
         (COALESCE(e."group2Quantity",0) * COALESCE(c."G2",0)) +
         (COALESCE(e."group3Quantity",0) * COALESCE(c."G3",0)) +
         (COALESCE(e."group4Quantity",0) * COALESCE(c."G4",0)) +
         (COALESCE(e."group5Quantity",0) * COALESCE(c."G5",0)))
         * ROUND(COALESCE(c."vendorCostPerEach",0),2),
    2)
    FROM calculationsForEventOfferDtlPCTOffRange c
    WHERE e."sku" = c."sku"
      AND e."offerNo" = c."offerNo"
      AND e."offerId" = c."offerId"
      AND c."OfferTypeId" IN (6);

--===============================================================================================================
-- UPDATE tEventOffer FOR STD RANGE PRICE
--===============================================================================================================

WITH EventOfferDtlSummaryForStdRangePrice AS (
    SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
        d."gst" AS gst_value,
        -- Forecast metrics
        ROUND(SUM(COALESCE(d."forecastCost", 0)), 2)             AS "forecastCost",
        ROUND(SUM(COALESCE(d."forecastSales", 0)), 2)            AS "forecastSales",
        ROUND(SUM(COALESCE(d."forecastTradeMargin$", 0)), 2)     AS "forecastTradeMargin$",
         CASE
            WHEN SUM(COALESCE(d."forecastSales", 0)) > 0
            THEN ROUND(
                (SUM(COALESCE(d."forecastTradeMargin$", 0)) / (SUM(COALESCE(d."forecastSales", 0))/(1+d."gst"))) * 100,
            2)
            ELSE 0
        END AS "forecastTradeMargin%",
		-- Units and incremental
        SUM(COALESCE(d."everydayUnits", 0))                      AS "everydayUnits",
        SUM(COALESCE(d."categoryforecast", 0))                   AS "forecastUnits",
        ROUND(SUM(COALESCE(d."incrementalTrade$", 0)), 2)        AS "incrementalTm$",
        ROUND(SUM(COALESCE(d."incrementalSales", 0)), 2)         AS "incrementalSales$",

        -- Scan support
        SUM(COALESCE(d."scanSupport$", 0) * COALESCE(d."categoryforecast", 0)) AS "totalScanSupport$",
        ROUND(SUM((COALESCE(d."LatestEffectiveCost", 0) * (COALESCE(d."scanSupport%", 0)/100) * COALESCE(d."categoryforecast", 0))),2) AS "totalScanSupport%"
    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."offerNo" = o."offerNumber" AND d."eventId" = o."eventId"
    WHERE  (o."OfferTypeId" IN (14))
	  AND d."offerNo" = o."offerNumber"
	  AND d."offerId" = o."offerId"
    GROUP BY d."offerId", d."eventId",   d."offerNo", d."gst"
)
UPDATE public."tEventOffer" AS o
SET
    -- Forecast metrics
    "forecastCost"          = s."forecastCost",
    "forecastSales"         = s."forecastSales",
    "forecastTradeMargin$"  = s."forecastTradeMargin$",
    "forecastTradeMargin%"  = s."forecastTradeMargin%",

    -- Units and incremental
    "everydayUnits"         = s."everydayUnits",
    "forecastUnits"         = CAST(s."forecastUnits" AS int),
    "incrementalTm$"        = s."incrementalTm$",
    "incrementalSales$"     = s."incrementalSales$",
    "incrementalUnits"      = CAST((s."forecastUnits" - s."everydayUnits") AS int),

    -- Scan supports
    "totalScanSupport$"     = s."totalScanSupport$",
    "totalScanSupport%"     = s."totalScanSupport%",

    -- Supplier income (derived)
    "totalSupplierIncome"   = s."totalScanSupport$" + s."totalScanSupport%" + COALESCE(o."spacePurchase", 0)
FROM EventOfferDtlSummaryForStdRangePrice s
WHERE o."offerId" = s."offerId"
  AND o."eventId" = s."eventId"
  AND o."offerNumber" = s."offerNo";

  WITH EventOfferDtlSummaryforAdvPriceForStdRangePrice AS (
    SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
        d."gst" AS gst_value,
		 d."clearanceIndicator",
         -- Pricing logic as per C#
        MAX(d."advertisedPriceGst")                 AS "advPrice",
        MIN(d."calculatedSaveValue")        AS "saveValue",
        MIN(d."everydayPriceGst")              AS "everydayPrice",
        MIN(d."calculatedSavePercentage") AS "savePercent"
		   
    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."offerNo" = o."offerNumber" AND d."eventId" = o."eventId"
    WHERE  (o."OfferTypeId" IN (14))
	   AND d."offerNo" = o."offerNumber"
	  AND d."offerId" = o."offerId"
	  AND (d."clearanceIndicator" <> 'Y' OR d."clearanceIndicator" IS NULL)
    GROUP BY d."offerId", d."eventId",  d."clearanceIndicator", d."offerNo", d."gst"
)
UPDATE public."tEventOffer" AS o
SET
    -- Price + savings
    "advertisedPrice"       = ROUND(s."advPrice" / (1 + s.gst_value), 2),
    "advertisedPriceGst"    = ROUND(s."advPrice", 2),
    "saveValue"             = ROUND(s."saveValue", 2),
    "everydayPriceGst"      = ROUND(s."everydayPrice", 2),
	"everydayPrice"         = ROUND(s."everydayPrice" / (1 + s.gst_value), 2),
    "savePercent" = ROUND(s."savePercent", 2)
	FROM EventOfferDtlSummaryforAdvPriceForStdRangePrice s
WHERE o."offerId" = s."offerId"
  AND o."eventId" = s."eventId"
  AND o."offerNumber" = s."offerNo";

--===============================================================================================================
-- UPDATE tEventOffer For PCT OFF RANGE
--===============================================================================================================

-- EventOfferDtlSummaryForPCTOffRange
  WITH EventOfferDtlSummaryforAdvPriceForPCTOffRange  AS (
         SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
        d."gst" AS gst_value,
		d."clearanceIndicator",
       
	   MIN(d."advertisedPriceGst")                 AS "advPrice",
        MIN(d."calculatedSaveValue")        AS "saveValue",
        MIN(d."everydayPriceGst")              AS "everydayPrice",
        MIN(d."calculatedSavePercentage") AS "savePercent"
		
    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."offerNo" = o."offerNumber" AND d."eventId" = o."eventId"
    WHERE  (o."OfferTypeId" IN (6))
	  AND d."offerNo" = o."offerNumber"
	  AND d."offerId" = o."offerId"
	  AND (d."clearanceIndicator" <> 'Y' OR d."clearanceIndicator" IS NULL)
    GROUP BY d."offerId", d."eventId", d."offerNo", d."clearanceIndicator", d."gst"
)
UPDATE public."tEventOffer" AS o
SET
    -- Price + savings
    "advertisedPrice"       = ROUND(s."advPrice" / (1 + s.gst_value), 2),
    "advertisedPriceGst"    = ROUND(s."advPrice", 2),
    "saveValue"             = ROUND(s."saveValue", 2),
    "everydayPriceGst"      = ROUND(s."everydayPrice", 2),
	"everydayPrice"         = ROUND(s."everydayPrice" / (1 + s.gst_value), 2),
    "calculatedSavePercent" = ROUND(s."savePercent", 2)
	
FROM EventOfferDtlSummaryforAdvPriceForPCTOffRange s
WHERE o."offerId" = s."offerId"
  AND o."offerNumber" = s."offerNo";

   WITH EventOfferDtlSummaryForPCTOffRange  AS (
         SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
        d."gst" AS gst_value,

        -- Forecast metrics
        ROUND(SUM(COALESCE(d."forecastCost", 0)), 2)             AS "forecastCost",
        ROUND(SUM(COALESCE(d."forecastSales", 0)), 2)            AS "forecastSales",
        ROUND(SUM(COALESCE(d."forecastTradeMargin$", 0)), 2)     AS "forecastTradeMargin$",
         CASE
            WHEN SUM(COALESCE(d."forecastSales", 0)) > 0
            THEN ROUND(
                (SUM(COALESCE(d."forecastTradeMargin$", 0)) / (SUM(COALESCE(d."forecastSales", 0))/(1+d."gst"))) * 100,
            2)
            ELSE 0
        END AS "forecastTradeMargin%",
        -- Units and incremental
        SUM(COALESCE(d."everydayUnits", 0))                      AS "everydayUnits",
        SUM(COALESCE(d."categoryforecast", 0))                   AS "forecastUnits",
        ROUND(SUM(COALESCE(d."incrementalTrade$", 0)), 2)        AS "incrementalTm$",
        ROUND(SUM(COALESCE(d."incrementalSales", 0)), 2)         AS "incrementalSales$",

        -- Scan support
        SUM(COALESCE(d."scanSupport$", 0) * COALESCE(d."categoryforecast", 0)) AS "totalScanSupport$",
        ROUND(SUM((COALESCE(d."LatestEffectiveCost", 0) * (COALESCE(d."scanSupport%", 0)/100) * COALESCE(d."categoryforecast", 0))),2) AS "totalScanSupport%"
		
    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."offerNo" = o."offerNumber" AND d."eventId" = o."eventId"
    WHERE  (o."OfferTypeId" IN (6))
	  AND d."offerNo" = o."offerNumber"
	  AND d."offerId" = o."offerId"
    GROUP BY d."offerId", d."eventId", d."offerNo", d."gst"
)
UPDATE public."tEventOffer" AS o
SET
    -- Forecast metrics
    "forecastCost"          = s."forecastCost",
    "forecastSales"         = s."forecastSales",
    "forecastTradeMargin$"  = s."forecastTradeMargin$",
    "forecastTradeMargin%"  = s."forecastTradeMargin%",

    -- Units and incremental
    "everydayUnits"         = s."everydayUnits",
    "forecastUnits"         = CAST(s."forecastUnits" AS int),
    "incrementalTm$"        = s."incrementalTm$",
    "incrementalSales$"     = s."incrementalSales$",
    "incrementalUnits"      = CAST((s."forecastUnits" - s."everydayUnits") AS int),

    -- Scan supports
    "totalScanSupport$"     = s."totalScanSupport$",
    "totalScanSupport%"     = s."totalScanSupport%",

    -- Supplier income (derived)
    "totalSupplierIncome"   = s."totalScanSupport$" + s."totalScanSupport%" + COALESCE(o."spacePurchase", 0)
FROM EventOfferDtlSummaryForPCTOffRange s
WHERE o."offerId" = s."offerId"
  AND o."offerNumber" = s."offerNo";

--===============================================================================================================
-- UPDATE tMudMapDetail For STD Range Price and PCT OFF RANGE
--===============================================================================================================

WITH EventOfferDetailAgg AS (
      SELECT
          "eventId",
          "offerId",
          MIN(CASE WHEN "fromPriceIndicator" = true
                   THEN "advertisedPriceGst" END) AS "minFromPrice"
      FROM public."tEventOfferDetail"
      GROUP BY "eventId", "offerId"
  ),
  
 RegularOffers AS (
    SELECT
        e."eventId",
        e."offerId",
        e."offerName",
        e."offerType",
		e."OfferTypeId",
        UPPER(ev."status"),
		 CASE
              WHEN e."fromPrice" = true
              THEN FLOOR(eod."minFromPrice")
              ELSE FLOOR(SUM(
                  CASE
                      WHEN COALESCE(e."advertisedPriceGst", 0) > 9999999 THEN 0
                      ELSE COALESCE(e."advertisedPriceGst", 0)
                  END
              ))
          END AS "advertisedPrice",
		
		FLOOR(SUM(
		    CASE 
		        WHEN COALESCE(e."everydayPriceGst", 0) > 9999999 THEN 0
		        ELSE COALESCE(e."everydayPriceGst", 0)
		    END
		)) AS "everydayPriceGST",
		
		FLOOR(SUM(
		    CASE 
		        WHEN COALESCE(e."saveValue", 0) > 9999999 THEN 0
		        ELSE COALESCE(e."saveValue", 0)
		    END
		)) AS "saveValue",
		
		CASE
		    WHEN SUM(
		        CASE 
		            WHEN COALESCE(e."savePercent", 0) > 9999999 THEN 0
		            ELSE FLOOR(COALESCE(e."savePercent", 0))
		        END
		    ) < 5 THEN 0
		    ELSE FLOOR(
		        SUM(
		            CASE 
		                WHEN COALESCE(e."savePercent", 0) > 9999999 THEN 0
		                ELSE FLOOR(COALESCE(e."savePercent", 0))
		            END
		        ) / 5
		    ) * 5
		END AS "savePercent",

        BOOL_OR(COALESCE(e."isClearance", FALSE)) AS clearance,
        BOOL_OR(COALESCE(e."isNew", FALSE)) AS new,
        BOOL_OR(COALESCE(e."isRewards", FALSE)) AS loyality,
        e."country",
        e."requiredQuantity" AS "RequiredQuantity",
        BOOL_OR(COALESCE(e."fromPrice", FALSE)) AS "fromPrice",
        e."offerQuantity" AS "PurchaseQuantity",
        e."freeQuantity" AS "FreeQuantity"
    FROM public."tEventOffer" AS e
    INNER JOIN public."tEvent" AS ev ON e."eventId" = ev."eventId"
	 LEFT JOIN EventOfferDetailAgg as eod ON eod."eventId"=e."eventId" AND eod."offerId"=e."offerId"
     
    WHERE e."OfferTypeId" NOT IN (4,15) 
      AND e."OfferTypeId" <> 3
      AND e."OfferTypeId" <> 5
      AND UPPER(ev."status") <> 'COMPLETED'
    GROUP BY
        e."eventId", e."offerId", e."offerName", e."offerType", e."OfferTypeId",UPPER(ev."status"),
        e."country", e."requiredQuantity", e."fromPrice", e."offerQuantity", e."freeQuantity", eod."minFromPrice"
)
UPDATE public."tMudMapDetail" AS m
SET
    "offerName" = r."offerName",
    "offerType" = r."offerType",
	"offerTypeId" = r."OfferTypeId",
    "advertisedPrice" = r."advertisedPrice",
    "savePercent" = r."savePercent",
    "saveValue" = r."saveValue",
	"everydayPrice" = r."everydayPriceGST",
    clearance = r.clearance,
    new = r.new,
    loyality = r.loyality,
    "eventOfferId" = r."offerId",
    country = r.country,
    "requiredQuantity" = r."RequiredQuantity",
    "fromPrice" = r."fromPrice",
    "purchaseQuantity" = r."PurchaseQuantity",
    "freeQuantity" = r."FreeQuantity"
FROM RegularOffers AS r
WHERE m."eventId" = r."eventId"
  AND m."eventOfferId" = r."offerId"
 ;
  

  RAISE NOTICE 'Event offer details updated successfully for all SKUs.';

  v_end_time := clock_timestamp();

    UPDATE execution_log
    SET status      = 'SUCCESS',
        end_time    = v_end_time,
        duration_ms = (EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000)::bigint
    WHERE id = v_log_id;

EXCEPTION
    WHEN OTHERS THEN
        v_end_time := clock_timestamp();

		 RAISE LOG 'Daily_Refresh_Job_Failed';

        UPDATE execution_log
        SET status      = 'FAILED',
            end_time    = v_end_time,
            duration_ms = (EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000)::bigint
        WHERE id = v_log_id;

        RAISE;
		
END;
$BODY$;
ALTER PROCEDURE public.sp_update_event_offer_detailspctstd()
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
