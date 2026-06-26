CREATE OR REPLACE PROCEDURE public.sp_update_event_offer_detail_header(
	IN p_offer_id integer,
	IN p_offer_no integer,
	IN p_offer_type_id integer,
	IN p_save_percent numeric,
	IN p_incremental_percent numeric,
	IN p_space_purchase numeric,
	IN p_advertised_price_gst numeric,
	IN p_total_multibuy_price numeric,
	IN p_required_qty integer)
LANGUAGE plpgsql
AS $BODY$
DECLARE 
    v_gst numeric;
    v_startdate date;
    v_enddate date;
    v_country text;
	v_channel text;
	v_eventChannel text;
BEGIN
	  ------------------------------------------------------------------
    SELECT 
        eh."startDate", 
        eh."endDate", 
        eh."country",
		eh."channel"
    INTO 
        v_startdate, 
        v_enddate, 
        v_country,
		v_eventChannel
    FROM "tEventOffer" eoh
    JOIN "tEvent" eh ON eh."eventId" = eoh."eventId"
    WHERE eoh."offerId" = p_offer_id
      AND eoh."offerNumber" = p_offer_no
    LIMIT 1;

    ------------------------------------------------------------------
    -- 2) Get GST for that country + event date
    ------------------------------------------------------------------
    SELECT (c."configvalue"->>'GST')::numeric
    INTO v_gst
    FROM "tConfig" c
    WHERE c."configtype" = 'GST'
      AND c."country" LIKE v_country || '%'
      AND v_startdate >= (c."configvalue"->>'StartDate')::date
      AND v_startdate <= COALESCE((c."configvalue"->>'EndDate')::date, '9999-12-31')
    ORDER BY (c."configvalue"->>'StartDate')::date DESC
    LIMIT 1;

	SELECT (config."configvalue" ->> 'channel')
	INTO v_channel
	FROM "tConfig" config
	WHERE config."configkey" = v_eventChannel
   AND config."country" = v_country
   AND config."configtype" = 'SalesType';
    -- ======================================================
    -- 1. Override savePercent & incrementalPercentage
    -- ======================================================
	IF p_offer_type_id = 6 THEN
	
	  
    UPDATE "tEventOffer"
    SET 
        "savePercent" = p_save_percent,
        "incrementalPercentage" = p_incremental_percent,
		"spacePurchase" = p_space_purchase
    WHERE "offerId" = p_offer_id
      AND "offerNumber" = p_offer_no
      AND "OfferTypeId" = p_offer_type_id;

    -- ======================================================
    -- 2. Update Event Offer Detail (same CTE logic as given)
    -- ======================================================

    WITH updateEventOfferDtlForPCTOffRange AS (
        SELECT
            eod."sku",
            eod."offerNo",
            eod."offerId",
            eoh."offerType",
			eoh."OfferTypeId",
            p."clearance",
            eoh."savePercent",
            rag."G0", rag."G1", rag."G2", rag."G3", rag."G4", rag."G5",
            (COALESCE(s."averageMonthlySales", 0) / 30.0) *
            ((COALESCE(eoh."endDate", eh."endDate") - COALESCE(eoh."startDate", eh."startDate")) + 1) AS calc_units,
            v_channel AS "salesType",
            v_gst AS gst_value,
            ppr."exchangeRatePrice",
            ppr."priceControlPlan",
            ppr."pricePoint2",
            p."vendorCostPerEach",
            p."nationalAvgCost" AS natAvgCost,
            eoh."incrementalPercentage",
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
        INNER JOIN "tPriceProductRules" ppr
            ON ppr."sku" = eod."sku"
			AND ppr."company" = eh."company"
        INNER JOIN "tProducts" p ON p."sku" = eod."sku"
          LEFT JOIN "tInventory" inv ON inv."sku" = eod."sku" and inv."company" IN (eh."company",'12','52')
		 LEFT JOIN "tSalesY1" s
            ON s."sku" = eod."sku"
           AND s."company" = eh."company"
		   AND s."salesType" = v_channel
        LEFT JOIN "tRegionalAreaGroupAllocation" rag
            ON rag."allocationGroup" = 'DEFAULT'
			AND rag."country" = eh."country"
        WHERE eoh."offerId" = p_offer_id
          AND eoh."offerNumber" = p_offer_no
          AND eoh."OfferTypeId" = p_offer_type_id
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId", eoh."offerType",
            eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            v_channel, v_gst,
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost",
            eoh."incrementalPercentage",
            rag."G0", rag."G1", rag."G2", rag."G3", rag."G4", rag."G5",
            eoh."savePercent", eod."everydayUnits", s."averageMonthlySales",
            eod."categoryforecast",
            p."clearance",
			eod."isCategoryForecastLocked",
			eoh."OfferTypeId"
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
                ELSE d."categoryforecast"
            END AS categoryFcst,
            CASE 
                WHEN d."clearance" = 'Y' 
                THEN ROUND(COALESCE(CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2" END, 0),2)
                ELSE ROUND(
                    COALESCE(CASE d."salesType"
                        WHEN 'CASH' THEN d."exchangeRatePrice"
                        WHEN 'P&C'  THEN d."priceControlPlan"
                        WHEN 'ACC'  THEN d."pricePoint2" 
                        END,0)
                    - (COALESCE(CASE d."salesType"
                        WHEN 'CASH' THEN d."exchangeRatePrice"
                        WHEN 'P&C'  THEN d."priceControlPlan"
                        WHEN 'ACC'  THEN d."pricePoint2" END,0) * d."savePercent"/100)
                ,2)
            END AS new_advertisedPriceGst,
            CASE 
                WHEN d."clearance" = 'Y' 
                THEN ROUND(
                    COALESCE(CASE d."salesType"
                        WHEN 'CASH' THEN d."exchangeRatePrice"
                        WHEN 'P&C'  THEN d."priceControlPlan"
                        WHEN 'ACC'  THEN d."pricePoint2" END,0)
                    / (1+ COALESCE(d.gst_value,0)),2)
                ELSE ROUND(
                    (COALESCE(CASE d."salesType"
                        WHEN 'CASH' THEN d."exchangeRatePrice"
                        WHEN 'P&C' THEN d."priceControlPlan"
                        WHEN 'ACC' THEN d."pricePoint2" END,0)
                    - (COALESCE(CASE d."salesType"
                        WHEN 'CASH' THEN d."exchangeRatePrice"
                        WHEN 'P&C' THEN d."priceControlPlan"
                        WHEN 'ACC' THEN d."pricePoint2" END,0)*d."savePercent"/100)) 
                    / (1+COALESCE(d.gst_value,0))
                ,2)
            END AS new_advertisedPrice
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
		"gst" = c.gst_value,
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
        "nationalAverageCost" = COALESCE(c.natAvgCost, 0),
        "forecastTradeMargin$" = ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2),
        "stockOnHandStore" = c.sohStore,
        "stockOnHandDC"    = c.sohDc,
        "LatestEffectiveCost" = ROUND(COALESCE(c."vendorCostPerEach",0),2),
        "categoryCost"        = COALESCE(c.natAvgCost, 0),
      
        "everydayExtendedUnitCost"  = ROUND(c.calc_units) * COALESCE(c.natAvgCost, 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units) * c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units) * COALESCE(c.new_advertisedPriceGst, 0),
        "everydayCost" = COALESCE(c.natAvgCost, 0),
        "incrementalSales"=Round(Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2) - (ROUND(c.calc_units)*c.new_everydayPriceGst),2),
        "incrementalTrade$" =  ROUND( ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2) - ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2)-ROUND(COALESCE(c."vendorCostPerEach",0),2) )*ROUND(c.calc_units),2), 2),
        "forecastTradeMargin%" = CASE 
        WHEN Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2) > 0
        THEN             
               ROUND(
			  ((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst)
			  / (c.categoryFcst * c.new_advertisedPrice)
			  * 100,
			  2
			)
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
      AND e."offerId" = p_offer_id
      AND e."offerNo" = p_offer_no;

    -- ======================================================
    -- 3. Rollup summary into tEventOffer  
    -- ======================================================

    WITH EventOfferDtlSummaryforAdvPriceForPCTOffRange  AS (
         SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
        v_gst AS gst_value,
		d."clearanceIndicator",
       
	   MIN(d."advertisedPriceGst")                 AS "advPrice",
        MIN(d."calculatedSaveValue")        AS "saveValue",
        MIN(d."everydayPriceGst")              AS "everydayPrice",
        MIN(d."calculatedSavePercentage") AS "savePercent"
		
    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."offerNo" = o."offerNumber" AND d."eventId" = o."eventId"
    WHERE  (o."OfferTypeId" IN (6))
	  AND d."offerNo" = p_offer_no
	  AND d."offerId" = p_offer_id
	  AND (d."clearanceIndicator" <> 'Y' OR d."clearanceIndicator" IS NULL)
    GROUP BY d."offerId", d."eventId", d."offerNo", d."clearanceIndicator"
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
        v_gst AS gst_value,

        -- Forecast metrics
        ROUND(SUM(COALESCE(d."forecastCost", 0)), 2)             AS "forecastCost",
        ROUND(SUM(COALESCE(d."forecastSales", 0)), 2)            AS "forecastSales",
        ROUND(SUM(COALESCE(d."forecastTradeMargin$", 0)), 2)     AS "forecastTradeMargin$",
         CASE
            WHEN SUM(COALESCE(d."forecastSales", 0)) > 0
            THEN ROUND(
                (SUM(COALESCE(d."forecastTradeMargin$", 0)) / SUM(COALESCE(d."forecastSales", 0))) * 100,
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
	  AND d."offerNo" = p_offer_no
	  AND d."offerId" = p_offer_id
    GROUP BY d."offerId", d."eventId", d."offerNo"
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
	END IF;

	IF p_offer_type_id = 14 THEN
	

	UPDATE "tEventOffer"
	 SET 
        "incrementalPercentage" = p_incremental_percent,
		"spacePurchase" = p_space_purchase,
		"advertisedPriceGst" = p_advertised_price_gst
    WHERE "offerId" = p_offer_id
      AND "offerNumber" = p_offer_no
      AND "OfferTypeId" = p_offer_type_id;
	  
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
            v_channel AS "salesType",
            v_gst AS gst_value,
            ppr."exchangeRatePrice",
            ppr."priceControlPlan",
            ppr."pricePoint2",
            p."vendorCostPerEach",
            p."nationalAvgCost" ,
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
        INNER JOIN "tPriceProductRules" ppr
            ON ppr."sku" = eod."sku"
			AND ppr."company" = eh."company"
        INNER JOIN "tProducts" p
            ON p."sku" = eod."sku"
        LEFT JOIN "tInventory" inv
            ON inv."sku" = eod."sku"
			AND inv."company" IN (eh."company",'12','52')
        LEFT JOIN "tRegionalAreaGroupAllocation" rag
             on rag."allocationGroup"='DEFAULT'
			 AND rag."country" = eh."country"
	    LEFT JOIN "tSalesY1" s
            ON s."sku" = eod."sku"
           AND s."company" = eh."company"
		   AND s."salesType" = v_channel
		WHERE eoh."OfferTypeId" IN (14)
		
	  AND eod."offerNo" = p_offer_no
	  AND eod."offerId" = p_offer_id
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId",eoh."offerType", 
            eoh."offerId", eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            v_channel, v_gst,
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost", p."clearance",
            eoh."incrementalPercentage", rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5", 
			eoh."advertisedPriceGst",
			s."averageMonthlySales",			
			eod."everydayUnits",
			eod."categoryforecast",
			eod."isCategoryForecastLocked",
			eoh."OfferTypeId"
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
			ELSE p_advertised_price_gst END AS new_advertisedPriceGst,
			CASE WHEN d."clearance" = 'Y' THEN ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            )/(1+ COALESCE(d.gst_value, 0)),2)
			ELSE ROUND((p_advertised_price_gst)/(1+ COALESCE(d.gst_value, 0)),2) END AS new_advertisedPrice,
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
		"gst" = c.gst_value,
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
        "LatestEffectiveCost" = ROUND(COALESCE(c."vendorCostPerEach",0),2),
        "categoryCost"        = COALESCE(c.natAvgCost, 0),
      
        "everydayExtendedUnitCost"  = ROUND(c.calc_units) * COALESCE(c.natAvgCost, 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units) * c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units) * COALESCE(c.new_advertisedPriceGst, 0),
        "everydayCost" = COALESCE(c.natAvgCost, 0),
       "incrementalSales"=Round(Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2) - (ROUND(c.calc_units)*c.new_everydayPriceGst),2),
        "incrementalTrade$" =  ROUND( ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2) - ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2)-ROUND(COALESCE(c."vendorCostPerEach",0),2) )*ROUND(c.calc_units),2), 2),
         "forecastTradeMargin%" = CASE 
        WHEN Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2) > 0
        THEN             
              ROUND(
			  ((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst)
			  / (c.categoryFcst * c.new_advertisedPrice)
			  * 100,
			  2
			)
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
	  
	-- STD RANGE PRICE
WITH EventOfferDtlSummaryForStdRangePrice AS (
    SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
        v_gst AS gst_value,
        -- Forecast metrics
        ROUND(SUM(COALESCE(d."forecastCost", 0)), 2)             AS "forecastCost",
        ROUND(SUM(COALESCE(d."forecastSales", 0)), 2)            AS "forecastSales",
        ROUND(SUM(COALESCE(d."forecastTradeMargin$", 0)), 2)     AS "forecastTradeMargin$",
         CASE
            WHEN SUM(COALESCE(d."forecastSales", 0)) > 0
            THEN ROUND(
                (SUM(COALESCE(d."forecastTradeMargin$", 0)) / SUM(COALESCE(d."forecastSales", 0))) * 100,
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
	  AND d."offerNo" = p_offer_no
	  AND d."offerId" = p_offer_id
    GROUP BY d."offerId", d."eventId",   d."offerNo"
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
        v_gst AS gst_value,
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
	  AND d."offerNo" = p_offer_no
	  AND d."offerId" = p_offer_id
	  AND (d."clearanceIndicator" <> 'Y' OR d."clearanceIndicator" IS NULL)
    GROUP BY d."offerId", d."eventId",  d."clearanceIndicator", d."offerNo"
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
	END IF;
	
		IF p_offer_type_id = 25 THEN

	  
		 UPDATE "tEventOffer"
	 SET 
        "incrementalPercentage" = p_incremental_percent,
		"spacePurchase" = p_space_purchase,
		"advertisedPriceGst" = p_advertised_price_gst
    WHERE "offerId" = p_offer_id
      AND "offerNumber" = p_offer_no
      AND "OfferTypeId" = p_offer_type_id;
	  
     WITH updateEventOfferDtlForComboList AS (
	
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
            v_channel AS "salesType",
            v_gst AS gst_value,
            ppr."exchangeRatePrice",
            ppr."priceControlPlan",
            ppr."pricePoint2",
            p."vendorCostPerEach",
            p."nationalAvgCost" ,
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
        INNER JOIN "tPriceProductRules" ppr
            ON ppr."sku" = eod."sku"
			AND ppr."company" = eh."company"
        INNER JOIN "tProducts" p
            ON p."sku" = eod."sku"
        LEFT JOIN "tInventory" inv
            ON inv."sku" = eod."sku"
			AND inv."company" IN (eh."company",'12','52')
        LEFT JOIN "tRegionalAreaGroupAllocation" rag
             on rag."allocationGroup"='DEFAULT'
			 AND rag."country" = eh."country"
	    LEFT JOIN "tSalesY1" s
            ON s."sku" = eod."sku"
           AND s."company" = eh."company"
		   AND s."salesType" = v_channel
		WHERE eoh."OfferTypeId" IN (25)
		
	  AND eod."offerNo" = p_offer_no
	  AND eod."offerId" = p_offer_id
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId",eoh."offerType", 
            eoh."offerId", eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            v_channel, v_gst,
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost", p."clearance",
            eoh."incrementalPercentage", rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5", 
			eoh."advertisedPriceGst",
			s."averageMonthlySales",	
			eod."isCategoryForecastLocked",
			eod."everydayUnits",
			eod."categoryforecast",
			eoh."OfferTypeId"
    ),

    calculationsForEventOfferDtlComboList AS (
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
			ELSE p_advertised_price_gst END AS new_advertisedPriceGst,
			CASE WHEN d."clearance" = 'Y' THEN ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            )/(1+ COALESCE(d.gst_value, 0)),2)
			ELSE ROUND((p_advertised_price_gst)/(1+ COALESCE(d.gst_value, 0)),2) END AS new_advertisedPrice,
			ROUND(d."nationalAvgCost",2) as natAvgCost
        FROM updateEventOfferDtlForComboList d
    )
    UPDATE "tEventOfferDetail" e
    SET
        "everydayUnits" = ROUND(c.calc_units),
        "everydayPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGst" = c.new_everydayPriceGst,
        "everydayPriceGstSys" = c.new_everydayPriceGst,
		"advertisedPriceGst" = c.new_advertisedPriceGst,
		"advertisedPrice" = c.new_advertisedPrice,
		"gst" = c.gst_value,
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
        "LatestEffectiveCost" = ROUND(COALESCE(c."vendorCostPerEach",0),2),
        "categoryCost"        = COALESCE(c.natAvgCost, 0),
      
        "everydayExtendedUnitCost"  = ROUND(c.calc_units) * COALESCE(c.natAvgCost, 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units) * c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units) * COALESCE(c.new_advertisedPriceGst, 0),
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
    FROM calculationsForEventOfferDtlComboList c
    WHERE e."sku" = c."sku"
      AND e."offerNo" = c."offerNo"
      AND e."offerId" = c."offerId"
      AND c."OfferTypeId" IN (25);
	  
	-- COMBO SKU LIST 
WITH EventOfferDtlSummaryForComboList AS (
    SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
        v_gst AS gst_value,
        -- Forecast metrics
        ROUND(SUM(COALESCE(d."forecastCost", 0)), 2)             AS "forecastCost",
        ROUND(SUM(COALESCE(d."forecastSales", 0)), 2)            AS "forecastSales",
        ROUND(SUM(COALESCE(d."forecastTradeMargin$", 0)), 2)     AS "forecastTradeMargin$",
        CASE
            WHEN SUM(COALESCE(d."forecastSales", 0)) > 0
            THEN ROUND(
                (SUM(COALESCE(d."forecastTradeMargin$", 0)) / SUM(COALESCE(d."forecastSales", 0))) * 100,
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
    WHERE  (o."OfferTypeId" IN (25))
	  AND d."offerNo" = p_offer_no
	  AND d."offerId" = p_offer_id
    GROUP BY d."offerId", d."eventId",   d."offerNo"
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
    "totalSupplierIncome"   = s."totalScanSupport$" + s."totalScanSupport%" 
FROM EventOfferDtlSummaryForComboList s
WHERE o."offerId" = s."offerId"
  AND o."eventId" = s."eventId"
  AND o."offerNumber" = s."offerNo";

  	-- COMBO SKU LIST 
WITH EventOfferDtlSummaryForAdvPriceForComboList AS (
    SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
		d."clearanceIndicator",
        v_gst AS gst_value,
          -- Pricing logic as per C#
        MAX(d."advertisedPriceGst")                 AS "advPrice",
        MIN(d."calculatedSaveValue")        AS "saveValue",
        MIN(d."everydayPriceGst")              AS "everydayPrice",
        MIN(d."calculatedSavePercentage") AS "savePercent"
		   
    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."offerNo" = o."offerNumber" AND d."eventId" = o."eventId"
    WHERE  (o."OfferTypeId" IN (25))
	  AND d."offerNo" = p_offer_no
	  AND (d."clearanceIndicator" <> 'Y' OR d."clearanceIndicator" IS NULL)
	  AND d."offerId" = p_offer_id
    GROUP BY d."offerId", d."eventId",   d."clearanceIndicator",d."offerNo"
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
FROM EventOfferDtlSummaryForAdvPriceForComboList s
WHERE o."offerId" = s."offerId"
  AND o."eventId" = s."eventId"
  AND o."offerNumber" = s."offerNo";
	END IF;
	
	IF p_offer_type_id = 15 THEN
	
	  
	UPDATE "tEventOffer"
	 SET 
        "incrementalPercentage" = p_incremental_percent,
		"spacePurchase" = p_space_purchase,
		"requiredQuantity" = p_required_qty,
		"totalMultiBuyPrice" = p_total_multibuy_price
    WHERE "offerId" = p_offer_id
      AND "offerNumber" = p_offer_no
      AND "OfferTypeId" = p_offer_type_id;
	 WITH updateEventOfferDtlForMultiBuySKUList AS (
        SELECT
            eod."sku",
            eod."offerNo",
            eod."offerId",
			eoh."OfferTypeId",
            eoh."offerType",
            p."clearance",
            rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",			
			eod."everydayUnits",
			eod."categoryforecast",
             rag."G5",
			 eod."isCategoryForecastLocked",
            (COALESCE(s."averageMonthlySales", 0) / 30.0) *
            ((COALESCE(eoh."endDate", eh."endDate") - COALESCE(eoh."startDate", eh."startDate")) + 1) AS calc_units,
            v_channel AS "salesType",
            v_gst AS gst_value,
            ppr."exchangeRatePrice",
            ppr."priceControlPlan",
            ppr."pricePoint2",
            p."vendorCostPerEach",
            p."nationalAvgCost" AS natAvgCost,
            eoh."incrementalPercentage",
			eoh."advertisedPriceGst",
            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") = 'STORE' THEN inv."onHand" END), 0) AS sohStore,
            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") <> 'STORE' THEN inv."onHand" END), 0) AS sohDc

        FROM "tEventOfferDetail" eod
        INNER JOIN "tEventOffer" eoh
            ON eod."offerId" = eoh."offerId"
           AND eod."offerNo" = eoh."offerNumber"
        INNER JOIN "tEvent" eh
            ON eh."eventId" = eoh."eventId"
        INNER JOIN "tPriceProductRules" ppr
            ON ppr."sku" = eod."sku"
			AND ppr."company" = eh."company"
        INNER JOIN "tProducts" p
            ON p."sku" = eod."sku"
        LEFT JOIN "tInventory" inv
            ON inv."sku" = eod."sku"
			AND inv."company" IN (eh."company", '12', '52')
		 LEFT JOIN "tSalesY1" s
             ON s."sku" = eod."sku"
           AND s."company" = eh."company"
		   AND s."salesType" = v_channel
        LEFT JOIN "tRegionalAreaGroupAllocation" rag
             on rag."allocationGroup"='DEFAULT'
			 AND rag."country" = eh."country"
		WHERE eoh."OfferTypeId" IN (15)
		
	  AND eod."offerNo" = p_offer_no
	  AND eod."offerId" = p_offer_id
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId",eoh."offerType", 
            eoh."offerId", eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            v_channel, v_gst,
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost", p."clearance",
            eoh."incrementalPercentage",rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5",
			eoh."advertisedPriceGst",
			eod."everydayUnits",
			eod."categoryforecast",
			s."averageMonthlySales",
			eod."isCategoryForecastLocked",
			eoh."OfferTypeId"
    ),

    calculationsForEventOfferDtlMultiBuySKUList AS (
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
			ELSE 
				CASE 
					WHEN p_required_qty <> 0 THEN 
						ROUND(p_total_multibuy_price/p_required_qty,2) 
					ELSE 0 
				END 
			END AS new_advertisedPriceGst,
			CASE 
			    WHEN d."clearance" = 'Y' THEN 
			        ROUND(
			            COALESCE(
			                CASE d."salesType"
			                    WHEN 'CASH' THEN d."exchangeRatePrice"
			                    WHEN 'P&C'  THEN d."priceControlPlan"
			                    WHEN 'ACC'  THEN d."pricePoint2"
			                    ELSE 0
			                END,
			            0) / (1 + COALESCE(d.gst_value, 0)),
			        2)
			
			    ELSE 
			        ROUND(
			            (
			                CASE 
			                    WHEN p_required_qty <> 0 THEN 
			                        ROUND(p_total_multibuy_price / p_required_qty)
			                    ELSE 0 
			                END
			            ) / (1 + COALESCE(d.gst_value, 0)),
			        2)
			END AS new_advertisedPrice

			
        FROM updateEventOfferDtlForMultiBuySKUList d
    )
    UPDATE "tEventOfferDetail" e
    SET
        "everydayUnits" = ROUND(c.calc_units),
        "everydayPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGst" = c.new_everydayPriceGst,
        "everydayPriceGstSys" = c.new_everydayPriceGst,
		"advertisedPriceGst"= c.new_advertisedPriceGst,
		"advertisedPrice" = c.new_advertisedPrice,
		"gst" = c.gst_value,
		"calculatedSaveValue"= Round(e."everydayPriceGst"-c.new_advertisedPriceGst,2),
		"calculatedSavePercentage" = CASE 
    WHEN c.new_everydayPriceGst > 0 THEN ROUND(((c.new_everydayPriceGst - c.new_advertisedPriceGst) / c.new_everydayPriceGst)* 100, 2)
    ELSE 0 
END,
		"categoryforecast" = c.categoryFcst,
		"incrementalForecast"=c.categoryFcst-ROUND(c.calc_units),
        "nationalAverageCost" = COALESCE(c.natAvgCost, 0),
		"clearanceIndicator" = CASE WHEN c."clearance" IS NULL OR TRIM(c."clearance") = '' THEN 'N' ELSE c."clearance" END,
        "forecastTradeMargin$" = ROUND((c.new_advertisedPrice - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2),
        "stockOnHandStore" = c.sohStore,
        "stockOnHandDC"    = c.sohDc,
        "LatestEffectiveCost" = ROUND(COALESCE(c."vendorCostPerEach",0),2),
        "categoryCost"        = COALESCE(c.natAvgCost, 0),
         "forecastCost"=Round(ROUND(COALESCE(c."vendorCostPerEach",0),2)*c.categoryFcst,2),
        "forecastSales"=Round(c.categoryFcst*ROUND(c.new_advertisedPriceGst,2),2),
        "everydayExtendedUnitCost"  = ROUND(c.calc_units) * COALESCE(c.natAvgCost, 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units) * c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units) * COALESCE(c.new_advertisedPriceGst, 0),
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
    FROM calculationsForEventOfferDtlMultiBuySKUList c
    WHERE e."sku" = c."sku"
      AND e."offerNo" = c."offerNo"
      AND e."offerId" = c."offerId"
      AND c."OfferTypeId" IN (15);

  WITH EventOfferDtlSummaryForMultiBuySKUList AS (
    SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
        v_gst AS gst_value,

        -- Forecast metrics
		ROUND(SUM(COALESCE(d."purchaseQuantity"))) 				 AS "purchaseQuantity",
        ROUND(SUM(COALESCE(d."forecastCost", 0)), 2)             AS "forecastCost",
        ROUND(SUM(COALESCE(d."forecastSales", 0)), 2)            AS "forecastSales",
        ROUND(SUM(COALESCE(d."forecastTradeMargin$", 0)), 2)     AS "forecastTradeMargin$",
        CASE
            WHEN SUM(COALESCE(d."forecastSales", 0)) > 0
            THEN ROUND(
                (SUM(COALESCE(d."forecastTradeMargin$", 0)) / SUM(COALESCE(d."forecastSales", 0))) * 100,
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
		
    WHERE  (o."OfferTypeId" IN (15))
	  AND d."offerNo" = p_offer_no
	  AND d."offerId" = p_offer_id
    GROUP BY d."offerId", d."eventId", d."offerNo"
)
UPDATE public."tEventOffer" AS o
SET
    -- Forecast metrics
    "forecastCost"          = s."forecastCost",
    "forecastSales"         = s."forecastSales",
    "forecastTradeMargin$"  = s."forecastTradeMargin$",
    "forecastTradeMargin%"  = s."forecastTradeMargin%",
	"purchaseQuantity"		= s."purchaseQuantity",
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
FROM EventOfferDtlSummaryForMultiBuySKUList s
WHERE o."offerId" = s."offerId"
  AND o."eventId" = s."eventId"
  AND o."offerNumber" = s."offerNo";

  	  WITH EventOfferDtlSummaryForAdvPriceForMultiBuySKUList AS (
    SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
        v_gst AS gst_value,
		d."clearanceIndicator",
       -- Pricing logic as per C#
        MAX(d."advertisedPriceGst")                 AS "advPrice",
        MIN(d."calculatedSaveValue")        AS "saveValue",
        MIN(d."everydayPriceGst")              AS "everydayPrice",
        MIN(d."calculatedSavePercentage") AS "savePercent"
		   
    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."offerNo" = o."offerNumber" AND d."eventId" = o."eventId"
		
    WHERE  (o."OfferTypeId" IN (15))
	  AND d."offerNo" = p_offer_no
	  AND d."offerId" = p_offer_id
	 AND (d."clearanceIndicator" <> 'Y' OR d."clearanceIndicator" IS NULL)
    GROUP BY d."offerId", d."eventId", d."clearanceIndicator", d."offerNo"
)
UPDATE public."tEventOffer" AS o
SET
  

    -- Price + savings
    "advertisedPrice"       = ROUND(s."advPrice" / (1 + s.gst_value), 2),
    "advertisedPriceGst"    = ROUND(s."advPrice", 2),
        "saveValue"             = ROUND(s."saveValue", 2)* o."requiredQuantity",
    "everydayPriceGst"      = ROUND(s."everydayPrice", 2),
	"everydayPrice"         = ROUND(s."everydayPrice" / (1 + s.gst_value), 2),
    "calculatedSavePercent" = ROUND(s."savePercent", 2)
	
FROM EventOfferDtlSummaryForAdvPriceForMultiBuySKUList s
WHERE o."offerId" = s."offerId"
  AND o."eventId" = s."eventId"
  AND o."offerNumber" = s."offerNo";
END IF;

	IF p_offer_type_id = 23 THEN

	UPDATE "tEventOffer"
	 SET 
        "incrementalPercentage" = p_incremental_percent,
		"spacePurchase" = p_space_purchase
    WHERE "offerId" = p_offer_id
      AND "offerNumber" = p_offer_no
      AND "OfferTypeId" = p_offer_type_id;

	   WITH updateEventOfferDtlForPriceOnlySKUList AS (
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
            v_channel AS "salesType",
            v_gst AS gst_value,
            ppr."exchangeRatePrice",
            ppr."priceControlPlan",
			eod."isCategoryForecastLocked",
            ppr."pricePoint2",
            p."vendorCostPerEach",
            p."nationalAvgCost" ,
            eoh."incrementalPercentage",			
			eod."everydayUnits",
			eod."categoryforecast",
            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") = 'STORE' THEN inv."onHand" END), 0) AS sohStore,
            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") <> 'STORE' THEN inv."onHand" END), 0) AS sohDc

        FROM "tEventOfferDetail" eod
        INNER JOIN "tEventOffer" eoh
            ON eod."offerId" = eoh."offerId"
           AND eod."offerNo" = eoh."offerNumber"
        INNER JOIN "tEvent" eh
            ON eh."eventId" = eoh."eventId"
        INNER JOIN "tPriceProductRules" ppr
            ON ppr."sku" = eod."sku"
			AND ppr."company" = eh."company"
        INNER JOIN "tProducts" p
            ON p."sku" = eod."sku"
        LEFT JOIN "tInventory" inv
            ON inv."sku" = eod."sku"
			AND inv."company" IN (eh."company",'12','52')
        LEFT JOIN "tRegionalAreaGroupAllocation" rag
             on rag."allocationGroup"='DEFAULT'
			 AND rag."country" = eh."country"
		LEFT JOIN "tSalesY1" s
             ON s."sku" = eod."sku"
           AND s."company" = eh."company"
		   AND s."salesType" = v_channel
		WHERE eoh."OfferTypeId" = 23
		
	  AND eod."offerNo" = p_offer_no
	  AND eod."offerId" = p_offer_id
        GROUP BY
            eod."sku", eod."offerNo", eod."offerId",eoh."offerType", 
            eoh."offerId", eoh."endDate", eoh."startDate", eh."endDate", eh."startDate",
            v_channel, v_gst,
            ppr."exchangeRatePrice", ppr."priceControlPlan", ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost", p."clearance",
            eoh."incrementalPercentage",rag."G0",
            rag."G1",
            rag."G2",
            rag."G3",
            rag."G4",
             rag."G5",			 
			eod."everydayUnits",
			eod."isCategoryForecastLocked",
			eod."categoryforecast",
			 s."averageMonthlySales",
			 eoh."OfferTypeId"
    ),

    calculationsForEventOfferDtlPriceOnlySKUList AS (
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
			ROUND(COALESCE(
                CASE d."salesType"
                    WHEN 'CASH' THEN d."exchangeRatePrice"
                    WHEN 'P&C'  THEN d."priceControlPlan"
                    WHEN 'ACC'  THEN d."pricePoint2"
                    ELSE 0
                END, 0
            )/ (1 + COALESCE(d.gst_value, 0)),2) AS new_everydayPriceExGst,
			CASE 
			WHEN d."isCategoryForecastLocked" = FALSE 
			THEN CAST(ROUND((d."incrementalPercentage"::numeric / 100)* ROUND(d.calc_units)::numeric) AS integer) 
			ELSE d."categoryforecast" END as categoryFcst,
			ROUND(d."nationalAvgCost",2) as natAvgCost
        FROM updateEventOfferDtlForPriceOnlySKUList d
    )
    ---Price Only (SKU LISt)
    UPDATE "tEventOfferDetail" e
    SET
        "everydayUnits" = ROUND(c.calc_units),
        "everydayPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGst" = c.new_everydayPriceGst,
		"advertisedPriceGst" = c.new_everydayPriceGst,
		"advertisedPrice" = Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2),
        "everydayPriceGstSys" = c.new_everydayPriceGst,
        "calculatedSaveValue"=0,
		"calculatedSavePercentage" = 0,
		"gst" = c.gst_value,
		"categoryforecast" = c.categoryFcst,
		 "forecastCost"=Round(ROUND(COALESCE(c."vendorCostPerEach",0),2)*c.categoryFcst,2),
        "forecastSales"=Round(c.categoryFcst*ROUND(c.new_everydayPriceGst,2),2),
        "incrementalForecast"=c.categoryFcst-ROUND(c.calc_units),
        "nationalAverageCost" = COALESCE(c.natAvgCost, 0),
		"clearanceIndicator" = CASE WHEN c."clearance" IS NULL OR TRIM(c."clearance") = '' THEN 'N' ELSE c."clearance" END,
          "forecastTradeMargin$" = ROUND((c.new_everydayPriceExGst - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2),
        "stockOnHandStore" = c.sohStore,
        "stockOnHandDC"    = c.sohDc,
        "LatestEffectiveCost" = ROUND(COALESCE(c."vendorCostPerEach", 0),2),
        "categoryCost"        = COALESCE(c.natAvgCost, 0),
      
        "everydayExtendedUnitCost"  = ROUND(c.calc_units) * COALESCE(c.natAvgCost, 0),
        "everydayExtendedUnitSales" = ROUND(c.calc_units) * c.new_everydayPriceGst,

        "extendedAdvertisedPrice" = ROUND(c.calc_units) * COALESCE(c.new_everydayPriceGst, 0),
        "everydayCost" = COALESCE(c.natAvgCost, 0),
        "incrementalSales"=Round(Round(c.categoryFcst*ROUND(c.new_everydayPriceGst,2),2) - (ROUND(c.calc_units)*c.new_everydayPriceGst),2),
        "incrementalTrade$" =  ROUND( ROUND((c.new_everydayPriceExGst - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst,2) - ROUND((Round(c.new_everydayPriceGst / (1 + COALESCE(c.gst_value, 0)),2)-ROUND(COALESCE(c."vendorCostPerEach",0),2) )*ROUND(c.calc_units),2), 2),
        "forecastTradeMargin%" = CASE 
        WHEN Round(c.categoryFcst*ROUND(c.new_everydayPriceGst,2),2) > 0
        THEN             
              ROUND(((c.new_everydayPriceExGst - ROUND(COALESCE(c."vendorCostPerEach",0),2)) * c.categoryFcst) / (c.categoryFcst * c.new_everydayPriceExGst) * 100, 2)
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
    FROM calculationsForEventOfferDtlPriceOnlySKUList c
    WHERE e."sku" = c."sku"
      AND e."offerNo" = c."offerNo"
      AND e."offerId" = c."offerId"
      AND c."OfferTypeId"=23;

 WITH EventOfferDtlSummaryForPriceOnlySKUList AS (
    SELECT
        d."offerId",
        d."eventId",
		d."offerNo",
		v_gst AS gst_value,
        -- Summed forecast values
        ROUND(SUM(COALESCE(d."forecastCost", 0)), 2)              AS "forecastCost",
        ROUND(SUM(COALESCE(d."forecastSales", 0)), 2)             AS "forecastSales",
        ROUND(SUM(COALESCE(d."forecastTradeMargin$", 0)), 2)      AS "forecastTradeMargin$",
        CASE
            WHEN SUM(COALESCE(d."forecastSales", 0)) > 0
            THEN ROUND(
                (SUM(COALESCE(d."forecastTradeMargin$", 0)) / SUM(COALESCE(d."forecastSales", 0))) * 100,
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
        MIN(d."everydayPriceGst")                       AS "everydayPrice",
        MIN(d."advertisedPriceGst")                  AS "advPrice",
        SUM(COALESCE(d."calculatedSaveValue", 0))                 AS "saveValue",
		MIN(COALESCE(d."calculatedSavePercentage", 0))                 AS "savePercent"
		
    FROM public."tEventOfferDetail" d
    INNER JOIN public."tEventOffer" o
        ON d."offerId" = o."offerId" AND d."offerNo" = o."offerNumber" AND d."eventId" = o."eventId"
    WHERE  (o."OfferTypeId" IN (23))
	
	  AND d."offerNo" = p_offer_no
	  AND d."offerId" = p_offer_id
    GROUP BY d."offerId", d."eventId", v_gst, d."offerNo"
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
	"savePercent"             = ROUND(s."savePercent", 2),
	"everydayPrice"         = ROUND(s."everydayPrice" / (1 + s.gst_value), 2),
    "everydayPriceGst"      = ROUND(s."everydayPrice", 2),

    -- Supplier income (derived)
    "totalSupplierIncome"   = s."totalScanSupport$" + s."totalScanSupport%" + COALESCE(o."spacePurchase", 0)
FROM EventOfferDtlSummaryForPriceOnlySKUList s
WHERE o."offerId" = s."offerId"
  AND o."eventId" = s."eventId"
  AND o."offerNumber" = s."offerNo";
END IF;
END;
$BODY$;
ALTER PROCEDURE public.sp_update_event_offer_detail_header(IN p_offer_id integer, IN p_offer_no integer, IN p_offer_type_id integer, IN p_save_percent numeric, IN p_incremental_percent numeric, IN p_space_purchase numeric, IN p_advertised_price_gst numeric, IN p_total_multibuy_price numeric, IN p_required_qty integer)
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
