CREATE OR REPLACE PROCEDURE public.sp_update_event_offer_detailslppobxgx()
LANGUAGE plpgsql
AS $BODY$
DECLARE
    v_start_time timestamptz;
    v_end_time   timestamptz;
    v_log_id     bigint;
    v_job_name   text := 'sp_update_event_offer_detailsLPPOBXGX';
BEGIN
    -- Force this procedure to use AEST (Australia/Sydney)
    SET LOCAL TIME ZONE 'Australia/Sydney';

    -- Get start time in AEST and insert STARTED log row
    v_start_time := clock_timestamp();

    INSERT INTO execution_log (job_name, status, start_time)
    VALUES (v_job_name, 'STARTED', v_start_time)
    RETURNING id INTO v_log_id;

-- ===================================================================================================
-- UPDATE tEventOfferDetail For Line And Price
--===============================================================================================================

	-- LINE & PRICE
	   WITH updateEventOfferDtlForLP AS (
        SELECT
            eod."sku",
            eod."offerNo",
            eod."offerId",
            eoh."offerType",
			eoh."OfferTypeId",
			eoh."spacePurchase",
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
			eoh."advertisedPriceGst",
			
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
		WHERE eoh."OfferTypeId" = 1
		AND UPPER(eh."status")<> 'COMPLETED'
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId",eoh."offerType", 
            eoh."offerId",  eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            config."configvalue",
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost", p."clearance",
           rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5", 
			 eoh."advertisedPriceGst",
			 s."averageMonthlySales",
			 eoh."OfferTypeId",
			 eod."gst",
			 eoh."spacePurchase"
    ),

    calculationsForEventOfferDtlLP AS (
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
			CASE WHEN d."clearance" = 'Y' THEN ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            ),2)
			ELSE ROUND(d."advertisedPriceGst",2)  END AS  new_advertisedPriceGst,
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
        FROM updateEventOfferDtlForLP d
    )
    --- LINE & PRICE
    UPDATE "tEventOfferDetail" e
    SET
        "everydayUnits" = ROUND(c.calc_units),
        "everydayPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGst" = c.new_everydayPriceGst,
        "everydayPriceGstSys" = c.new_everydayPriceGst,
		"clearanceIndicator" = CASE WHEN c."clearance" IS NULL OR TRIM(c."clearance") = '' THEN 'N' ELSE c."clearance" END,
		"advertisedPriceGst" = c.new_advertisedPriceGst,
		"advertisedPrice" = c.new_advertisedPrice,
         "calculatedSaveValue"=Round(c.new_everydayPriceGst-c.new_advertisedPriceGst,2),
		"calculatedSavePercentage" = CASE 
    WHEN c.new_everydayPriceGst > 0 THEN ROUND(((c.new_everydayPriceGst - c.new_advertisedPriceGst) / c.new_everydayPriceGst) * 100, 2) 
    ELSE 0 
END,
        "incrementalForecast"=e."categoryforecast"-ROUND(c.calc_units),
        "nationalAverageCost" = COALESCE(c.natAvgCost, 0),
         "forecastTradeMargin$" = ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * e."categoryforecast",2),
        "stockOnHandStore" = c.sohStore,
        "stockOnHandDC"    = c.sohDc,
        "LatestEffectiveCost" = ROUND(COALESCE(c."vendorCostPerEach",0),2),
        "categoryCost"        = COALESCE(c.natAvgCost, 0),
      	"forecastCost"=Round(ROUND(COALESCE(c."vendorCostPerEach",0),2)*e."categoryforecast",2),
        "forecastSales"=Round(e."categoryforecast"*ROUND(c.new_advertisedPriceGst,2),2),
        "everydayExtendedUnitCost"  = ROUND(c.calc_units )* COALESCE(c.natAvgCost, 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units )* c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units) * COALESCE(c.new_advertisedPriceGst, 0),
 		"everydayCost" = COALESCE(c.natAvgCost, 0),
        
       "incrementalSales"=Round(Round(e."categoryforecast"*ROUND(c.new_advertisedPriceGst,2),2) - (ROUND(c.calc_units)*c.new_everydayPriceGst),2),
        "incrementalTrade$" =  ROUND( ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * e."categoryforecast",2) - ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2)-ROUND(COALESCE(c."vendorCostPerEach",0),2) )*ROUND(c.calc_units),2), 2),
        "forecastTradeMargin%" = CASE 
        WHEN Round(e."categoryforecast"*ROUND(c.new_advertisedPriceGst,2),2) > 0
        THEN             
               ROUND(((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * e."categoryforecast") / (e."categoryforecast" * c.new_advertisedPrice) * 100, 2)

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
    FROM calculationsForEventOfferDtlLP c
    WHERE e."sku" = c."sku"
      AND e."offerNo" = c."offerNo"
      AND e."offerId" = c."offerId"
      AND c."OfferTypeId"=1;

-- ===================================================================================================
-- UPDATE tEventOfferDetail For Price Only
--===============================================================================================================

-- PRICE ONLY
 WITH updateEventOfferDtlForPriceOnly AS (
        SELECT
            eod."sku",
            eod."offerNo",
            eod."offerId",
            eoh."offerType",
			eoh."OfferTypeId",
            p."clearance",
			eoh."spacePurchase",
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
		WHERE eoh."OfferTypeId" = 13
		AND UPPER(eh."status")<> 'COMPLETED'
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId",eoh."offerType", 
            eoh."offerId", eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            config."configvalue",
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost", p."clearance",
         rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5",
			 eoh."spacePurchase",
			 s."averageMonthlySales",
			 eoh."OfferTypeId",
			 eod."gst"
    ),

    calculationsForEventOfferDtlPriceOnly AS (
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
			ROUND(d."nationalAvgCost",2) as natAvgCost
        FROM updateEventOfferDtlForPriceOnly d
    )
    --Price Only (SKU LISt)
    UPDATE "tEventOfferDetail" e
    SET
        "everydayUnits" = ROUND(c.calc_units),
        "everydayPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGst" = c.new_everydayPriceGst,
		"advertisedPriceGst" = c.new_everydayPriceGst,
		"clearanceIndicator" = CASE WHEN c."clearance" IS NULL OR TRIM(c."clearance") = '' THEN 'N' ELSE c."clearance" END,
		"advertisedPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGstSys" = c.new_everydayPriceGst,
        "calculatedSaveValue"=0,
		"calculatedSavePercentage" = 0,
		"forecastCost"=Round(ROUND(COALESCE(c."vendorCostPerEach",0),2)*e."categoryforecast",2),
        "forecastSales"=Round(e."categoryforecast"*ROUND(c.new_everydayPriceGst,2),2),
        "incrementalForecast"=e."categoryforecast"-ROUND(c.calc_units),
        "nationalAverageCost" = COALESCE(c.natAvgCost, 0),
        "forecastTradeMargin$" = ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2)- ROUND(COALESCE(c."vendorCostPerEach",0),2)) * e."categoryforecast",2),
        "stockOnHandStore" = c.sohStore,
        "stockOnHandDC"    = c.sohDc,
        "LatestEffectiveCost" = ROUND(COALESCE(c."vendorCostPerEach",0),2),
        "categoryCost"        = COALESCE(c.natAvgCost, 0),
      
        "everydayExtendedUnitCost"  = ROUND(c.calc_units )* COALESCE(c.natAvgCost, 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units )* c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units )* COALESCE(c.new_everydayPriceGst, 0),
        "everydayCost" = COALESCE(c.natAvgCost, 0),
        "incrementalSales"=Round(Round(e."categoryforecast"*ROUND(c.new_everydayPriceGst,2),2) - (ROUND(c.calc_units)*c.new_everydayPriceGst),2),
        "incrementalTrade$" =  ROUND( ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2) - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * e."categoryforecast",2) - ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2)-ROUND(COALESCE(c."vendorCostPerEach",0),2) )*ROUND(c.calc_units),2), 2),
        "forecastTradeMargin%" = CASE 
        WHEN Round(e."categoryforecast"*ROUND(c.new_everydayPriceGst,2),2) > 0
        THEN             
               ROUND(((c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)) - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * e."categoryforecast") / (e."categoryforecast" * Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2))*100, 2)

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
    FROM calculationsForEventOfferDtlPriceOnly c
    WHERE e."sku" = c."sku"
      AND e."offerNo" = c."offerNo"
      AND e."offerId" = c."offerId"
      AND c."OfferTypeId"=13;

-- ===================================================================================================
-- UPDATE tEventOfferDetail For BXGX
--===============================================================================================================

--updateEventOfferDtl_BXGX
    WITH updateEventOfferDtlForBXGX AS (
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
			 eoh."spacePurchase",
            (COALESCE(s."averageMonthlySales", 0) / 30.0) *
            ((COALESCE(eoh."endDate", eh."endDate") - COALESCE(eoh."startDate", eh."startDate")) + 1) AS calc_units,
            config."configvalue"->>'channel' AS "salesType",
            eod."gst" AS gst_value,
            ppr."exchangeRatePrice",
            ppr."priceControlPlan",
            ppr."pricePoint2",
            p."vendorCostPerEach",
            p."nationalAvgCost",
			eoh."advertisedPriceGst",
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
		WHERE eoh."OfferTypeId" IN (17)
		AND UPPER(eh."status")<> 'COMPLETED'
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId",eoh."offerType", 
            eoh."offerId",  eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            config."configvalue",
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost", p."clearance",
           rag."G0",
            rag."G1",
            rag."G2",
			eoh."spacePurchase",
            rag."G3",
            rag."G4",
             rag."G5", 
			eoh."advertisedPriceGst",
			s."averageMonthlySales",
			eoh."OfferTypeId",
			eod."gst"
    ),

    calculationsForEventOfferDtlBXGX AS (
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
        FROM updateEventOfferDtlForBXGX d
    )
    UPDATE "tEventOfferDetail" e
    SET
        "everydayUnits" = ROUND(c.calc_units),
        "everydayPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGst" = c.new_everydayPriceGst,
        "everydayPriceGstSys" = c.new_everydayPriceGst,
		"advertisedPriceGst" = c.new_advertisedPriceGst,
		"advertisedPrice" =c.new_advertisedPrice,
		"calculatedSaveValue"= Round(c.new_everydayPriceGst-c.new_advertisedPriceGst,2),
		"calculatedSavePercentage" = CASE 
    WHEN c.new_everydayPriceGst > 0 THEN ROUND(((c.new_everydayPriceGst - c.new_advertisedPriceGst) / c.new_everydayPriceGst) * 100, 2)
    ELSE 0 
END,
        "incrementalForecast"=e."categoryforecast"-ROUND(c.calc_units),
        "nationalAverageCost" = COALESCE(c.natAvgCost, 0),
         "forecastTradeMargin$" = ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * e."categoryforecast",2),
		"clearanceIndicator" = CASE WHEN c."clearance" IS NULL OR TRIM(c."clearance") = '' THEN 'N' ELSE c."clearance" END,
        "stockOnHandStore" = c.sohStore,
        "stockOnHandDC"    = c.sohDc,
        "LatestEffectiveCost" = ROUND(COALESCE(c."vendorCostPerEach",0),2),
        "categoryCost"        = COALESCE(c.natAvgCost, 0),
        "forecastCost"=Round(ROUND(COALESCE(c."vendorCostPerEach",0),2)*e."categoryforecast",2),
        "forecastSales"=Round(e."categoryforecast"*ROUND(c.new_advertisedPriceGst,2),2),
        "everydayExtendedUnitCost"  = ROUND(c.calc_units) * COALESCE(c.natAvgCost, 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units )* c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units )* COALESCE( c.new_advertisedPriceGst, 0),
        "everydayCost" = COALESCE(c.natAvgCost, 0),
        "incrementalSales"=Round(Round(e."categoryforecast"*ROUND(c.new_advertisedPriceGst,2),2) - (ROUND(c.calc_units)*c.new_everydayPriceGst),2),
        "incrementalTrade$" =  ROUND( ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * e."categoryforecast",2) - ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2)-ROUND(COALESCE(c."vendorCostPerEach",0),2) )*ROUND(c.calc_units),2), 2),
        "forecastTradeMargin%" = CASE 
        WHEN Round(e."categoryforecast"*ROUND(c.new_advertisedPriceGst,2),2) > 0
        THEN             
               ROUND(((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * e."categoryforecast") / (e."categoryforecast" * c.new_advertisedPrice) * 100, 2)
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
    FROM calculationsForEventOfferDtlBXGX c
    WHERE e."sku" = c."sku"
      AND e."offerNo" = c."offerNo"
      AND e."offerId" = c."offerId"
      AND c."OfferTypeId" IN (17);

--===============================================================================================================
-- UPDATE tEventOffer For Line and Price & BXGX
--===============================================================================================================

--updateEventOfferDtlLP_BXGX
WITH EventOfferDtlSummaryForLP_BXGX AS (
    SELECT
        d."offerId",
        d."eventId",
		d."clearanceIndicator",
		d."gst" AS gst_value,
        -- Summed forecast values
        ROUND(SUM(COALESCE(d."forecastCost", 0)), 2)              AS "forecastCost",
        ROUND(SUM(COALESCE(d."forecastSales", 0)), 2)             AS "forecastSales",
        ROUND(SUM(COALESCE(d."forecastTradeMargin$", 0)), 2)      AS "forecastTradeMargin$",
        CASE
            WHEN SUM(COALESCE(d."forecastSales", 0)) > 0
            THEN ROUND(
                (SUM(COALESCE(d."forecastTradeMargin$", 0)) / (SUM(COALESCE(d."forecastSales", 0))/(1+d."gst"))) * 100,
            2)
            ELSE 0
        END AS "forecastTradeMargin%",
        ROUND(SUM(COALESCE(d."incrementalTrade$", 0)), 2)         AS "incrementalTm$",
        ROUND(SUM(COALESCE(d."incrementalSales", 0)), 2)          AS "incrementalSales$",

        -- Units and forecast
		SUM(COALESCE(d."categoryforecast", 0))                   AS "forecastUnits",
        SUM(COALESCE(d."everydayUnits", 0))                       AS "everydayUnits",
        SUM(COALESCE(d."scanSupport$", 0) * COALESCE(d."categoryforecast", 0)) AS "totalScanSupport$",
        ROUND(SUM((COALESCE(d."LatestEffectiveCost", 0) * (COALESCE(d."scanSupport%", 0)/100) * COALESCE(d."categoryforecast", 0))),2) AS "totalScanSupport%",
        -- Pricing
        MIN(d."everydayPrice")                       AS "everydayPrice",
		MIN(d."everydayPriceGst")                       AS "everydayPriceGst",
        SUM(COALESCE(d."advertisedPriceGst", 0))                  AS "advPrice",
        SUM(COALESCE(d."calculatedSaveValue", 0))                 AS "saveValue",
		SUM(COALESCE(d."calculatedSavePercentage", 0))                 AS "savePercent"

    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."eventId" = o."eventId"
    INNER JOIN public."tEvent" ev
        ON o."eventId" = ev."eventId"
    WHERE UPPER(ev."status")<> 'COMPLETED'
      AND (o."OfferTypeId" IN (1,17))
    GROUP BY d."offerId", d."eventId",d."clearanceIndicator",d."gst"
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
    "incrementalTm$"        = s."incrementalTm$",
    "incrementalSales$"     = s."incrementalSales$",
    "incrementalUnits"      = CAST((s."forecastUnits" - s."everydayUnits") AS int),
    "totalScanSupport%"     = s."totalScanSupport%",

    -- Price + savings
    "advertisedPrice"       = ROUND(s."advPrice" / (1 + s.gst_value), 2),
    "advertisedPriceGst"    = ROUND(s."advPrice", 2),
    "saveValue"             = ROUND(s."saveValue", 2),
    "everydayPriceGst"      = ROUND(s."everydayPriceGst", 2),
	"everydayPrice"      = ROUND(s."everydayPrice", 2),
	"savePercent" = ROUND(s."savePercent", 2),
	"isClearance" = CASE WHEN s."clearanceIndicator" = 'Y' THEN true ELSE false END,
    -- Supplier income (derived)
    "totalSupplierIncome"   = s."totalScanSupport$" + s."totalScanSupport%" + COALESCE(o."spacePurchase", 0)
FROM EventOfferDtlSummaryForLP_BXGX s
WHERE o."offerId" = s."offerId"
  AND o."eventId" = s."eventId"
 ;

--===============================================================================================================
-- UPDATE tEventOffer For Price Only
--===============================================================================================================

  WITH EventOfferDtlSummaryForPriceOnly AS (
    SELECT
        d."offerId",
        d."eventId",
		d."clearanceIndicator",
		d."gst" AS gst_value,
        -- Summed forecast values
        ROUND(SUM(COALESCE(d."forecastCost", 0)), 2)              AS "forecastCost",
        ROUND(SUM(COALESCE(d."forecastSales", 0)), 2)             AS "forecastSales",
        ROUND(SUM(COALESCE(d."forecastTradeMargin$", 0)), 2)      AS "forecastTradeMargin$",
        CASE
            WHEN SUM(COALESCE(d."forecastSales", 0)) > 0
            THEN ROUND(
                (SUM(COALESCE(d."forecastTradeMargin$", 0)) / (SUM(COALESCE(d."forecastSales", 0))/(1+d."gst"))) * 100,
            2)
            ELSE 0
        END AS "forecastTradeMargin%",
        ROUND(SUM(COALESCE(d."incrementalTrade$", 0)), 2)         AS "incrementalTm$",
        ROUND(SUM(COALESCE(d."incrementalSales", 0)), 2)          AS "incrementalSales$",

        -- Units and forecast
        SUM(COALESCE(d."everydayUnits", 0))                       AS "everydayUnits",
        SUM(COALESCE(d."categoryforecast", 0))                    AS "forecastUnits",

        -- Scan supports
        SUM(COALESCE(d."scanSupport$", 0) * COALESCE(d."categoryforecast", 0)) AS "totalScanSupport$",
        ROUND(SUM((COALESCE(d."LatestEffectiveCost", 0) * (COALESCE(d."scanSupport%", 0)/100) * COALESCE(d."categoryforecast", 0))),2) AS "totalScanSupport%",
        -- Pricing
        MIN(d."everydayPrice")                       AS "everydayPrice",
		MIN(d."everydayPriceGst")                       AS "everydayPriceGst",
        MAX(d."advertisedPriceGst")                  AS "advPrice",
        SUM(COALESCE(d."calculatedSaveValue", 0))                 AS "saveValue",
		SUM(COALESCE(d."calculatedSavePercentage", 0))                 AS "savePercent"
		
    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."eventId" = o."eventId"
    INNER JOIN public."tEvent" ev
        ON o."eventId" = ev."eventId"
    WHERE UPPER(ev."status")<> 'COMPLETED'
      AND (o."OfferTypeId" IN (13))
    GROUP BY d."offerId", d."eventId",d."clearanceIndicator",d."gst"
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

    -- Price + savings
    "advertisedPrice"       = ROUND(s."advPrice" / (1 + s.gst_value), 2),
    "advertisedPriceGst"    = ROUND(s."advPrice", 2),
    "saveValue"             = ROUND(s."saveValue", 2),
    "everydayPriceGst"      = ROUND(s."everydayPriceGst", 2),
	"everydayPrice"      = ROUND(s."everydayPrice", 2),
	"savePercent" = ROUND(s."savePercent", 2),
	"isClearance" = CASE WHEN s."clearanceIndicator" = 'Y' THEN true ELSE false END,
    -- Supplier income (derived)
    "totalSupplierIncome"   = s."totalScanSupport$" + s."totalScanSupport%" + COALESCE(o."spacePurchase", 0)
FROM EventOfferDtlSummaryForPriceOnly s
WHERE o."offerId" = s."offerId"
  AND o."eventId" = s."eventId";

--===============================================================================================================
-- UPDATE tMudMapDetail For Line&Price PriceOnly and BXGX
--===============================================================================================================

WITH RegularOffers AS (
    SELECT
        e."eventId",
        e."offerId",
        e."offerName",
        e."offerType",
		e."OfferTypeId",
        ev."status",
        FLOOR(SUM(
		    CASE 
		        WHEN COALESCE(e."advertisedPriceGst", 0) > 9999999 THEN 0
		        ELSE COALESCE(e."advertisedPriceGst", 0)
		    END
		)) AS "advertisedPrice",
		
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
        e."purchaseQuantity" AS "PurchaseQuantity",
        e."freeQuantity" AS "FreeQuantity"
    FROM public."tEventOffer" AS e
    INNER JOIN public."tEvent" AS ev ON e."eventId" = ev."eventId"
    WHERE e."OfferTypeId" NOT IN (4,15) 
      AND e."OfferTypeId" <> 3
      AND e."OfferTypeId" <> 5
      AND UPPER(ev."status")<> 'COMPLETED'
    GROUP BY
        e."eventId", e."offerId", e."offerName", e."offerType", e."OfferTypeId",ev."status",
        e."country", e."requiredQuantity", e."fromPrice", e."purchaseQuantity", e."freeQuantity"
)
-- update tMudMapDetail RegularOffers
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
        -- Log failure too
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
ALTER PROCEDURE public.sp_update_event_offer_detailslppobxgx()
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
