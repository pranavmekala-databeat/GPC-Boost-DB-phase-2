CREATE OR REPLACE PROCEDURE public.sp_update_lecost_natavgcost(
	IN p_offerid integer,
	IN p_offerno integer,
	OUT p_lowestedprice numeric)
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
      AND eoh."offerNumber" = p_offerno
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
          AND d."offerNo" = p_offerNo
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

    ----------------------------------------------------------------------
    -- STEP 2 → UPDATE IMAGE & COPY REFERENCES
    ----------------------------------------------------------------------
    WITH latest_offer AS (
        SELECT 
            o."imageReference",
            o."copyReference"
        FROM "tEventOffer" o
        INNER JOIN "tEventOfferDetail" d
            ON o."offerNumber" = d."offerNo"
           AND o."offerId" = d."offerId"
        INNER JOIN "tEvent" h
            ON o."eventId" = h."eventId"
        INNER JOIN "tEventOffer" curr_offer
            ON curr_offer."offerId" = p_offerId
           AND curr_offer."offerNumber" = p_offerNo
        INNER JOIN "tEvent" curr
            ON curr."eventId" = curr_offer."eventId"
        WHERE 
            h."eventId" <> curr."eventId"
            AND d."sku" IN (
                SELECT "sku" FROM "tEventOfferDetail"
                WHERE "offerId" = p_offerId AND "offerNo" = p_offerNo
            )
            AND h."channel" = curr."channel"
            AND h."company" = curr."company"
            AND h."country" = curr."country"
            AND h."eventType" = curr."eventType"
            AND o."offerType" = curr_offer."offerType"
            AND h."startDate" >= CURRENT_DATE - INTERVAL '13 months'
            AND o."imageReference" IS NOT NULL
            AND o."copyReference" IS NOT NULL
        ORDER BY h."startDate" DESC
        LIMIT 1
    ),
    latest_offer_by_name AS (
        SELECT 
            o."imageReference",
            o."copyReference"
        FROM "tEventOffer" o
        INNER JOIN "tEvent" h
            ON o."eventId" = h."eventId"
        INNER JOIN "tEventOffer" curr_offer
            ON curr_offer."offerId" = p_offerId
           AND curr_offer."offerNumber" = p_offerNo
        INNER JOIN "tEvent" curr
            ON curr."eventId" = curr_offer."eventId"
        WHERE 
            h."channel" = curr."channel"
            AND h."company" = curr."company"
            AND h."country" = curr."country"
            AND h."eventType" = curr."eventType"
            AND o."offerType" = curr_offer."offerType"
            AND o."offerName" = curr_offer."offerName"
            AND o."offerType" IN ('COMBO', 'BUY X GET Y FREE')
            AND h."startDate" >= CURRENT_DATE - INTERVAL '13 months'
            AND o."imageReference" IS NOT NULL
            AND o."copyReference" IS NOT NULL
        ORDER BY h."startDate" DESC
        LIMIT 1
    )
    UPDATE "tEventOffer" o
    SET 
        "imageReference" = COALESCE(lo."imageReference", lon."imageReference"),
        "copyReference"  = COALESCE(lo."copyReference", lon."copyReference")
    FROM latest_offer lo
    FULL JOIN latest_offer_by_name lon ON TRUE
    WHERE o."offerId" = p_offerId
      AND o."offerNumber" = p_offerNo
      AND o."OfferTypeId" IN 
        (1,3,4,5,13,17);

	 SELECT MIN(COALESCE("everydayPriceGst", 0))
    INTO p_lowestEdPrice
    FROM "tEventOfferDetail"
    WHERE "offerNo" = p_offerNo
      AND "offerId" = p_offerId;

END;
$BODY$;
ALTER PROCEDURE public.sp_update_lecost_natavgcost(IN p_offerid integer, IN p_offerno integer, OUT p_lowestedprice numeric)
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
