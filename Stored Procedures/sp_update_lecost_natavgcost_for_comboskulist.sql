CREATE OR REPLACE PROCEDURE public.sp_update_lecost_natavgcost_for_comboskulist(
	IN p_offerid integer)
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
    WHERE eoh."offerId" = p_offerid
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
    ----------------------------------------------------------------------
    -- STEP 1 → UPDATE COSTS IN tEventOfferDetail
    ----------------------------------------------------------------------
    WITH data AS (
        SELECT
            d."sku",
            d."offerNo",
            d."offerId",
            s."averageMonthlySales",
            (COALESCE(s."averageMonthlySales", 0) / 30.0) *
            ((COALESCE(eoh."endDate", eh."endDate") -
              COALESCE(eoh."startDate", eh."startDate")) + 1) AS calc_units,

            v_channel AS "salesType",
            v_gst AS gst_value,

            ppr."exchangeRatePrice",
            ppr."priceControlPlan",
            ppr."pricePoint2",

            p."vendorCostPerEach",
            p."nationalAvgCost",

            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") = 'STORE' THEN inv."onHand" END), 0) AS sohStore,
            COALESCE(SUM(CASE WHEN UPPER(inv."locationType") <> 'STORE' THEN inv."onHand" END), 0) AS sohDc

        FROM "tEventOfferDetail" d
        INNER JOIN "tEventOffer" eoh
            ON d."offerId" = eoh."offerId"
           AND d."offerNo" = eoh."offerNumber"
        INNER JOIN "tEvent" eh
            ON eh."eventId" = eoh."eventId"
			INNER JOIN "tProducts" p
            ON p."sku" = d."sku"
          INNER JOIN "tPriceProductRules" ppr
            ON ppr."sku" = d."sku"
            AND ppr."company" = eh."company"
            and ppr."supplierId"=p."supplierId"
            and ppr."startDate"<=CURRENT_DATE and  ppr."endDate">=CURRENT_DATE
        
		LEFT JOIN "tSalesY1" s
            ON s."sku" = d."sku"
           AND s."company" = eh."company"
           AND s."salesType" = v_channel
        LEFT JOIN "tInventory" inv
            ON inv."sku" = d."sku"
			and inv."company" in (eh."company",'12','52')
        WHERE d."offerId" = p_offerId
        GROUP BY
            d."sku", d."offerNo", d."offerId",
            eoh."offerId", s."averageMonthlySales",
            eoh."endDate", eoh."startDate",
            eh."endDate", eh."startDate",
            v_channel, v_gst,
            ppr."exchangeRatePrice", ppr."priceControlPlan",
            ppr."pricePoint2",
            p."vendorCostPerEach", p."nationalAvgCost"
    )
    UPDATE "tEventOfferDetail" e
    SET
        "everydayUnits" = ROUND(d.calc_units),

        "everydayPrice" =
            ROUND(COALESCE( CASE d."salesType"
                WHEN 'CASH' THEN d."exchangeRatePrice"
                WHEN 'P&C'  THEN d."priceControlPlan"
                WHEN 'ACC'  THEN d."pricePoint2"
                ELSE 0 END, 0) / (1 + COALESCE(d.gst_value, 0)),2),

        "everydayPriceGst" = ROUND(COALESCE(
            CASE d."salesType"
                WHEN 'CASH' THEN d."exchangeRatePrice"
                WHEN 'P&C'  THEN d."priceControlPlan"
                WHEN 'ACC'  THEN d."pricePoint2"
                ELSE 0 END, 0),2),

        "everydayPriceGstSys" = ROUND(COALESCE(
            CASE d."salesType"
                WHEN 'CASH' THEN d."exchangeRatePrice"
                WHEN 'P&C'  THEN d."priceControlPlan"
                WHEN 'ACC'  THEN d."pricePoint2"
                ELSE 0 END, 0),2),

        "stockOnHandStore" = d.sohStore,
        "stockOnHandDC"    = d.sohDc,
		"gst" = d.gst_value,
        "LatestEffectiveCost"      = ROUND(COALESCE(d."vendorCostPerEach", 0),2),
        "nationalAverageCost"      = ROUND(COALESCE(d."nationalAvgCost", 0),2),
        "categoryCost"             = ROUND(COALESCE(d."nationalAvgCost", 0),2),

        "everydayExtendedUnitCost"  = ROUND(d.calc_units) * ROUND(COALESCE(d."nationalAvgCost", 0),2),
        "everydayExtendedUnitSales" = ROUND(d.calc_units) * ROUND(COALESCE(
                                              CASE d."salesType"
                                                WHEN 'CASH' THEN d."exchangeRatePrice"
                                                WHEN 'P&C'  THEN d."priceControlPlan"
                                                WHEN 'ACC'  THEN d."pricePoint2"
                                                ELSE 0 END, 0),2),

        "extendedAdvertisedPrice" = ROUND(d.calc_units) * ROUND(COALESCE(e."advertisedPrice", 0),2),
        "everydayCost" = ROUND(COALESCE(d."nationalAvgCost", 0),2),
		"isCategoryForecastLocked" =
								    CASE 
								        WHEN e."isSkuEdited" IS FALSE OR e."isSkuEdited" IS NULL
								        THEN FALSE
								        ELSE e."isCategoryForecastLocked"
								    END
    FROM data d
    WHERE e."sku" = d."sku"
      AND e."offerNo" = d."offerNo"
      AND e."offerId" = d."offerId";

END;
$BODY$;
ALTER PROCEDURE public.sp_update_lecost_natavgcost_for_comboskulist(IN p_offerid integer)
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
