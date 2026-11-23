-- Q01. Active driver headcount.
SELECT COUNT(*) AS active_driver_count
FROM driver
WHERE left_date IS NULL;

-- Q02. Total platform GMV.
Select sum (amount) as  total_gmv_eur
FROM payment
Where status ='succeeded';

--Q03. Total refund exposure.
Select Sum(amount) AS total_refunded_eur
From payment
Where status = 'refunded';

--Q04. Customer base split.
select
    customer_type,
    Count(*) AS customer_count
From customer
Group BY customer_type
Order BY customer_type ASC
Limit 5;

--Q05. Voucher pool size.
Select count (DISTINCT trip.rider_customer_id) AS voucher_eligible_customer_count
from trip
WHERE LOWER(TRIM(status)) IN ('cancelled_by_rider','cancelled_by_driver',
    'aborted','no_show','noshow');

--Q06. Busiest pickup zones. 
select
TRIM(z.zone_name) AS zone_name,
COUNT(t.trip_id) AS trip_count
FROM trip t
JOIN zone z
ON t.pickup_zone_id = z.zone_id
GROUP BY TRIM(z.zone_name)
ORDER BY trip_count DESC,
    zone_name ASC
LIMIT 10;

--Q07. Average ride fare by source.
SELECT t.source_system,
    ROUND(AVG(p.amount), 2) AS avg_ride_fare_eur
FROM trip t
JOIN payment p ON p.service_id = t.trip_id::TEXT
    AND p.service_type = 'ride'
WHERE LOWER(TRIM(p.status)) = 'succeeded'
    AND COALESCE(p.payment_correction_flag, FALSE) = FALSE
GROUP BY t.source_system
ORDER BY avg_ride_fare_eur DESC,
    t.source_system ASC
LIMIT 5;

--Q08. Payment success rate by service.
SELECT CASE WHEN payment_correction_flag = TRUE
AND LOWER(TRIM(service_type)) = 'ride'
THEN 'package'
ELSE LOWER(TRIM(service_type))
END AS service_type_corrected,
COUNT(*) AS total_attempts,
COUNT(*) FILTER (
WHERE LOWER(TRIM(status)) = 'succeeded') AS successful_attempts,
 ROUND( COUNT(*) FILTER ( WHERE LOWER(TRIM(status)) = 'succeeded'
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS success_rate_percent
FROM payment GROUP BY
CASE
WHEN payment_correction_flag = TRUE
AND LOWER(TRIM(service_type)) = 'ride'
THEN 'package'
ELSE LOWER(TRIM(service_type))
END
ORDER BY success_rate_percent DESC,
    service_type_corrected ASC
LIMIT 5;

--Q09. Trip outcome breakdown.
SELECT CASE
WHEN LOWER(TRIM(status)) = 'finished' THEN 'completed'
WHEN LOWER(TRIM(status)) = 'aborted' THEN 'cancelled_by_rider'
WHEN LOWER(TRIM(status)) IN ('no_show', 'noshow') THEN 'no_show'
ELSE LOWER(TRIM(status))
END AS status_normalized,
COUNT(*) AS trip_count
FROM trip
GROUP BY status_normalized
ORDER BY status_normalized
LIMIT 10;

--Q10. Premium fare zones. 
SELECT
    CASE
        WHEN LOWER(TRIM(z.zone_name)) = 'prenzlauer-berg'
            THEN 'Prenzlauer Berg'
        ELSE TRIM(z.zone_name)
    END AS zone_name_canonical,

    COUNT(t.trip_id) AS completed_ride_count,

    ROUND(AVG(p.amount), 2) AS avg_fare_eur
FROM trip t
JOIN zone z
    ON t.pickup_zone_id = z.zone_id
JOIN payment p
    ON p.service_id = t.trip_id::TEXT
    AND p.service_type = 'ride'

WHERE LOWER(TRIM(t.status)) IN ('completed', 'finished')
    AND LOWER(TRIM(p.status)) = 'succeeded'
    AND COALESCE(p.payment_correction_flag, FALSE) = FALSE

GROUP BY
    CASE
        WHEN LOWER(TRIM(z.zone_name)) = 'prenzlauer-berg'
            THEN 'Prenzlauer Berg'
        ELSE TRIM(z.zone_name)
    END

ORDER BY
    avg_fare_eur DESC,
    zone_name_canonical ASC

LIMIT 10;

--Q11. Top-rated drivers leaderboard.
SELECT
    d.driver_id,
    d.driver_name,

    ROUND(
        AVG(
            CASE
                WHEN LOWER(TRIM(r.source_system)) = 'quickhop'
                    THEN r.score / 2.0
                ELSE r.score
            END
        ),
        2
    ) AS avg_normalized_rating,

    COUNT(DISTINCT t.trip_id) AS rated_ride_count

FROM trip t

JOIN driver d
    ON t.driver_id = d.driver_id

JOIN rating r
    ON r.service_id = t.trip_id::TEXT
    AND r.service_type = 'ride'

WHERE r.score IS NOT NULL

GROUP BY
    d.driver_id,
    d.driver_name

HAVING COUNT(DISTINCT t.trip_id) >= 30

ORDER BY
    avg_normalized_rating DESC,
    rated_ride_count DESC,
    d.driver_id ASC

LIMIT 20;

--Q12. Pending merge queue.
WITH normalized_customers AS (
    SELECT
        customer_id,
        source_system,
        merged_into_customer_id,
        email,
        REGEXP_REPLACE(phone, '\D', '', 'g') AS phone_digits
    FROM customer
    WHERE phone IS NOT NULL
),
phones AS (
    SELECT
        *,
        CASE
            WHEN LOWER(TRIM(source_system)) = 'quickhop'
                 AND phone_digits LIKE '490%'
                THEN '49' || SUBSTRING(phone_digits FROM 4)
            ELSE phone_digits
        END AS phone_normalized
    FROM normalized_customers
)
SELECT
    g.customer_id AS goride_customer_id,
    q.customer_id AS quickhop_customer_id,
    g.phone_normalized,
    g.email
FROM phones g
JOIN phones q
    ON g.phone_normalized = q.phone_normalized
WHERE LOWER(TRIM(g.source_system)) = 'goride'
  AND LOWER(TRIM(q.source_system)) = 'quickhop'
  AND g.merged_into_customer_id IS NULL
  AND q.merged_into_customer_id IS NULL
  AND g.phone_normalized <> ''
ORDER BY
    g.email ASC,
    g.customer_id ASC
LIMIT 200;

--Q13. Parcel-heavy zones for ride cross-sell.
WITH service_volume AS (
    SELECT
        CASE
            WHEN LOWER(TRIM(z.zone_name)) = 'prenzlauer-berg'
                THEN 'Prenzlauer Berg'
            ELSE TRIM(z.zone_name)
        END AS zone_name_canonical,
        'ride' AS service_type
    FROM trip t
    JOIN zone z
        ON t.pickup_zone_id = z.zone_id

    UNION ALL

    SELECT
        CASE
            WHEN LOWER(TRIM(z.zone_name)) = 'prenzlauer-berg'
                THEN 'Prenzlauer Berg'
            ELSE TRIM(z.zone_name)
        END AS zone_name_canonical,
        'parcel' AS service_type
    FROM package_delivery pd
    JOIN zone z
        ON pd.pickup_zone_id = z.zone_id
),
zone_counts AS (
    SELECT
        zone_name_canonical,
        COUNT(*) FILTER (
            WHERE service_type = 'ride'
        ) AS ride_count,
        COUNT(*) FILTER (
            WHERE service_type = 'parcel'
        ) AS parcel_count
    FROM service_volume
    GROUP BY zone_name_canonical
)
SELECT
    zone_name_canonical,
    ride_count,
    parcel_count,
    ROUND(
        parcel_count * 100.0 /
        NULLIF(ride_count + parcel_count, 0),
        2
    ) AS parcel_share_percent
FROM zone_counts
WHERE parcel_count * 100.0 /
      NULLIF(ride_count + parcel_count, 0) > 18
ORDER BY
    parcel_share_percent DESC,
    zone_name_canonical ASC
LIMIT 25;

--Q14. Advertising target zones.
WITH zone_ride_counts AS (
    SELECT
        CASE
            WHEN LOWER(TRIM(z.zone_name)) = 'prenzlauer-berg'
                THEN 'Prenzlauer Berg'
            ELSE TRIM(z.zone_name)
        END AS zone_name_canonical,
        COUNT(t.trip_id) AS total_rides,
        COUNT(t.trip_id) FILTER (
            WHERE LOWER(TRIM(t.status)) IN (
                'cancelled_by_rider',
                'cancelled_by_driver',
                'aborted',
                'no_show',
                'noshow'
            )
        ) AS cancelled_rides
    FROM trip t
    JOIN zone z
        ON t.pickup_zone_id = z.zone_id
    GROUP BY
        CASE
            WHEN LOWER(TRIM(z.zone_name)) = 'prenzlauer-berg'
                THEN 'Prenzlauer Berg'
            ELSE TRIM(z.zone_name)
        END
)
SELECT
    zone_name_canonical,
    total_rides,
    cancelled_rides,
    ROUND(
        cancelled_rides * 100.0 /
        NULLIF(total_rides, 0),
        2
    ) AS cancellation_rate_percent
FROM zone_ride_counts
WHERE total_rides < 1100
  AND cancelled_rides * 100.0 /
      NULLIF(total_rides, 0) > 25
ORDER BY
    cancellation_rate_percent DESC,
    zone_name_canonical ASC
LIMIT 25;

--Q15. Top revenue vehicles.
WITH successful_payments AS (
    SELECT
        CASE
            WHEN LOWER(TRIM(service_type)) = 'ride'
                 AND COALESCE(payment_correction_flag, FALSE) = TRUE
                THEN 'package'
            ELSE LOWER(TRIM(service_type))
        END AS service_type_corrected,
        service_id,
        amount
    FROM payment
    WHERE LOWER(TRIM(status)) = 'succeeded'
),
vehicle_revenue AS (
    SELECT
        t.vehicle_id,
        sp.amount
    FROM trip t
    JOIN successful_payments sp
        ON sp.service_id = t.trip_id::TEXT
       AND sp.service_type_corrected = 'ride'

    UNION ALL

    SELECT
        pd.vehicle_id,
        sp.amount
    FROM package_delivery pd
    JOIN successful_payments sp
        ON sp.service_id = pd.delivery_id::TEXT
       AND sp.service_type_corrected = 'package'
)
SELECT
    v.vehicle_id,
    v.license_plate,
    ROUND(SUM(vr.amount), 2) AS total_revenue_eur
FROM vehicle_revenue vr
JOIN vehicle v
    ON vr.vehicle_id = v.vehicle_id
GROUP BY
    v.vehicle_id,
    v.license_plate
ORDER BY
    total_revenue_eur DESC,
    v.vehicle_id ASC
LIMIT 5;

--Q16. Revenue mix for the board. 
WITH corrected_payments AS (
    SELECT
        p.service_id,
        CASE
            WHEN LOWER(TRIM(p.service_type)) = 'ride'
                 AND COALESCE(p.payment_correction_flag, FALSE) = TRUE
                THEN 'package'
            ELSE LOWER(TRIM(p.service_type))
        END AS service_type_corrected,
        p.amount
    FROM payment p
    WHERE LOWER(TRIM(p.status)) = 'succeeded'
),
service_revenue AS (
       SELECT
        t.source_system,
        cp.service_type_corrected,
        t.rider_customer_id AS payer_customer_id,
        cp.amount
    FROM trip t
    JOIN corrected_payments cp
        ON cp.service_id = t.trip_id::TEXT
       AND cp.service_type_corrected = 'ride'

    UNION ALL   
    SELECT
        pd.source_system,
        cp.service_type_corrected,
        pd.sender_customer_id AS payer_customer_id,
        cp.amount
    FROM package_delivery pd
    JOIN corrected_payments cp
        ON cp.service_id = pd.delivery_id::TEXT
       AND cp.service_type_corrected = 'package'
)
SELECT
    sr.source_system,
    sr.service_type_corrected,
    LOWER(TRIM(c.customer_type)) AS customer_type,
    ROUND(SUM(sr.amount), 2) AS total_revenue_eur
FROM service_revenue sr
JOIN customer c
    ON sr.payer_customer_id = c.customer_id
GROUP BY
    sr.source_system,
    sr.service_type_corrected,
    LOWER(TRIM(c.customer_type))
ORDER BY
    total_revenue_eur DESC,
    sr.source_system ASC,
    sr.service_type_corrected ASC,
    customer_type ASC
LIMIT 25;

--Q17. Payment service-type reconciliation errors. 
SELECT
    p.payment_id,
    LOWER(TRIM(p.service_type)) AS claimed_service_type,
    CASE
        WHEN t.trip_id IS NOT NULL THEN 'ride'
        WHEN pd.delivery_id IS NOT NULL THEN 'package'
    END AS actual_service_type,
    p.service_id
FROM payment p
LEFT JOIN trip t
    ON p.service_id = t.trip_id::TEXT
LEFT JOIN package_delivery pd
    ON p.service_id = pd.delivery_id::TEXT
WHERE
    (
        LOWER(TRIM(p.service_type)) = 'ride'
        AND pd.delivery_id IS NOT NULL
    )
    OR
    (
        LOWER(TRIM(p.service_type)) = 'package'
        AND t.trip_id IS NOT NULL
    )
ORDER BY
    p.payment_id ASC
LIMIT 100;

--Q18. Lapsed customers for win-back.
WITH customer_identity AS (
    SELECT
        customer_id,
        COALESCE(merged_into_customer_id, customer_id) AS master_customer_id
    FROM customer
),
completed_rides AS (
    SELECT
        ci.master_customer_id,
        t.trip_id,
        t.completed_at
    FROM trip t
    JOIN customer_identity ci
        ON t.rider_customer_id = ci.customer_id
    WHERE LOWER(TRIM(t.status)) IN ('completed', 'finished')
      AND t.completed_at IS NOT NULL
),
customer_ride_summary AS (
    SELECT
        cr.master_customer_id,
        COUNT(DISTINCT cr.trip_id) AS total_completed_rides,
        MAX(cr.completed_at) AS last_ride_date
    FROM completed_rides cr
    GROUP BY cr.master_customer_id
),
latest_database_ride AS (
    SELECT
        MAX(completed_at) AS latest_completed_ride
    FROM trip
    WHERE LOWER(TRIM(status)) IN ('completed', 'finished')
      AND completed_at IS NOT NULL
)
SELECT
    crs.master_customer_id,
    master.email,
    crs.total_completed_rides,
    crs.last_ride_date,
    (ldr.latest_completed_ride::DATE - crs.last_ride_date::DATE)
        AS days_since_last_ride
FROM customer_ride_summary crs
JOIN customer master
    ON master.customer_id = crs.master_customer_id
CROSS JOIN latest_database_ride ldr
WHERE LOWER(TRIM(master.customer_type)) = 'individual'
  AND crs.total_completed_rides >= 3
  AND crs.last_ride_date <= ldr.latest_completed_ride - INTERVAL '60 days'
ORDER BY
    days_since_last_ride DESC,
    crs.last_ride_date ASC,
    crs.master_customer_id ASC
LIMIT 100;

--Q19. Berlin zones by average monthly rider spending. 

WITH successful_ride_payments AS (
    SELECT
        p.service_id,
        p.amount
    FROM payment p
    WHERE LOWER(TRIM(p.status)) = 'succeeded'
      AND LOWER(TRIM(p.service_type)) = 'ride'
      AND COALESCE(p.payment_correction_flag, FALSE) = FALSE
),
ride_spending AS (
    SELECT
        CASE
            WHEN LOWER(TRIM(z.zone_name)) = 'prenzlauer-berg'
                THEN 'Prenzlauer Berg'
            ELSE TRIM(z.zone_name)
        END AS zone_name_canonical,
        t.rider_customer_id,
        DATE_TRUNC('month', t.requested_at) AS ride_month,
        srp.amount
    FROM trip t
    JOIN zone z
        ON t.pickup_zone_id = z.zone_id
    JOIN successful_ride_payments srp
        ON srp.service_id = t.trip_id::TEXT
),
zone_monthly_summary AS (
    SELECT
        zone_name_canonical,
        COUNT(DISTINCT (rider_customer_id, ride_month))
            AS distinct_rider_months,
        SUM(amount) AS total_zone_spend_eur
    FROM ride_spending
    GROUP BY zone_name_canonical
)
SELECT
    zone_name_canonical,
    distinct_rider_months,
    ROUND(total_zone_spend_eur, 2) AS total_zone_spend_eur,
    ROUND(
        total_zone_spend_eur / NULLIF(distinct_rider_months, 0),
        2
    ) AS avg_spending_per_rider_per_month_eur
FROM zone_monthly_summary
ORDER BY
    avg_spending_per_rider_per_month_eur DESC,
    zone_name_canonical ASC
LIMIT 25;

--Q20. Top earners by average monthly revenue.

WITH completed_services AS (
    SELECT
        COALESCE(d.merged_into_driver_id, d.driver_id) AS master_driver_id,
        t.trip_id::TEXT AS service_id,
        'ride' AS service_type,
        DATE_TRUNC('month', t.requested_at) AS service_month
    FROM trip t
    JOIN driver d
        ON t.driver_id = d.driver_id
    WHERE LOWER(TRIM(t.status)) IN ('completed', 'finished')
      AND t.requested_at IS NOT NULL

    UNION ALL
    SELECT
        COALESCE(d.merged_into_driver_id, d.driver_id) AS master_driver_id,
        pd.delivery_id::TEXT AS service_id,
        'package' AS service_type,
        DATE_TRUNC('month', pd.requested_at) AS service_month
    FROM package_delivery pd
    JOIN driver d
        ON pd.driver_id = d.driver_id
    WHERE LOWER(TRIM(pd.status)) = 'delivered'
      AND pd.requested_at IS NOT NULL
),
driver_active_months AS (
    SELECT
        master_driver_id,
        COUNT(DISTINCT service_month) AS active_months
    FROM completed_services
    GROUP BY master_driver_id
),
corrected_payments AS (
    SELECT
        service_id,
        CASE
            WHEN LOWER(TRIM(service_type)) = 'ride'
                 AND COALESCE(payment_correction_flag, FALSE) = TRUE
                THEN 'package'
            ELSE LOWER(TRIM(service_type))
        END AS service_type_corrected,
        amount
    FROM payment
    WHERE LOWER(TRIM(status)) = 'succeeded'
),
driver_revenue AS (
    SELECT
        cs.master_driver_id,
        SUM(cp.amount) AS total_revenue_eur
    FROM completed_services cs
    JOIN corrected_payments cp
        ON cp.service_id = cs.service_id
       AND cp.service_type_corrected = cs.service_type
    GROUP BY cs.master_driver_id
)
SELECT
    dam.master_driver_id,
    master_driver.driver_name,
    dam.active_months,
    ROUND(COALESCE(dr.total_revenue_eur, 0), 2) AS total_revenue_eur,
    ROUND(
        COALESCE(dr.total_revenue_eur, 0) /
        NULLIF(dam.active_months, 0),
        2
    ) AS avg_monthly_revenue_eur
FROM driver_active_months dam
JOIN driver master_driver
    ON master_driver.driver_id = dam.master_driver_id
LEFT JOIN driver_revenue dr
    ON dr.master_driver_id = dam.master_driver_id
ORDER BY
    avg_monthly_revenue_eur DESC,
    dam.master_driver_id ASC
LIMIT 20;

--Q21. Refund-impact on revenue.
WITH corrected_payments AS (
    SELECT
        p.service_id,
        CASE
            WHEN LOWER(TRIM(p.service_type)) = 'ride'
                 AND COALESCE(p.payment_correction_flag, FALSE) = TRUE
                THEN 'package'
            ELSE LOWER(TRIM(p.service_type))
        END AS service_type_corrected,
        p.amount,
        LOWER(TRIM(p.status)) AS payment_status
    FROM payment p
),
payment_revenue AS (
    SELECT
        t.source_system,
        cp.service_type_corrected,
        cp.amount,
        cp.payment_status
    FROM trip t
    JOIN corrected_payments cp
        ON cp.service_id = t.trip_id::TEXT
       AND cp.service_type_corrected = 'ride'

    UNION ALL
    SELECT
        pd.source_system,
        cp.service_type_corrected,
        cp.amount,
        cp.payment_status
    FROM package_delivery pd
    JOIN corrected_payments cp
        ON cp.service_id = pd.delivery_id::TEXT
       AND cp.service_type_corrected = 'package'
)
SELECT
    source_system,
    service_type_corrected,
    ROUND(
        SUM(amount) FILTER (
            WHERE payment_status = 'succeeded'
        ),
        2
    ) AS collected_revenue_eur,
    ROUND(
        SUM(amount) FILTER (
            WHERE payment_status = 'refunded'
        ),
        2
    ) AS refunded_revenue_eur,
    ROUND(
        COALESCE(
            SUM(amount) FILTER (
                WHERE payment_status = 'succeeded'
            ),
            0
        )
        -
        COALESCE(
            SUM(amount) FILTER (
                WHERE payment_status = 'refunded'
            ),
            0
        ),
        2
    ) AS net_revenue_eur
FROM payment_revenue
GROUP BY
    source_system,
    service_type_corrected
ORDER BY
    net_revenue_eur DESC,
    source_system ASC,
    service_type_corrected ASC
LIMIT 25;

--Q22. Top businesses by average monthly spend. 

WITH business_parcels AS (
    SELECT
        c.customer_id,
        c.business_name,
        pd.delivery_id,
        pd.requested_at,
        DATE_TRUNC('month', pd.requested_at) AS delivery_month
    FROM package_delivery pd
    JOIN customer c
        ON pd.sender_customer_id = c.customer_id
    WHERE LOWER(TRIM(c.customer_type)) = 'business'
      AND pd.requested_at IS NOT NULL
),
business_active_months AS (
    SELECT
        customer_id,
        business_name,
        COUNT(DISTINCT delivery_month) AS active_months
    FROM business_parcels
    GROUP BY
        customer_id,
        business_name
),
corrected_payments AS (
    SELECT
        p.service_id,
        CASE
            WHEN LOWER(TRIM(p.service_type)) = 'ride'
                 AND COALESCE(p.payment_correction_flag, FALSE) = TRUE
                THEN 'package'
            ELSE LOWER(TRIM(p.service_type))
        END AS service_type_corrected,
        p.amount
    FROM payment p
    WHERE LOWER(TRIM(p.status)) = 'succeeded'
),
business_parcel_revenue AS (
    SELECT
        bp.customer_id,
        SUM(cp.amount) AS total_spend_eur
    FROM business_parcels bp
    JOIN corrected_payments cp
        ON cp.service_id = bp.delivery_id::TEXT
       AND cp.service_type_corrected = 'package'
    GROUP BY bp.customer_id
)
SELECT
    bam.customer_id,
    bam.business_name,
    bam.active_months,
    ROUND(COALESCE(bpr.total_spend_eur, 0), 2) AS total_spend_eur,
    ROUND(
        COALESCE(bpr.total_spend_eur, 0) /
        NULLIF(bam.active_months, 0),
        2
    ) AS avg_monthly_spend_eur
FROM business_active_months bam
LEFT JOIN business_parcel_revenue bpr
    ON bpr.customer_id = bam.customer_id
ORDER BY
    avg_monthly_spend_eur DESC,
    bam.customer_id ASC
LIMIT 20;

--Q23. Fraud detection: cancelled trips with kept payments.
WITH payment_base AS (
    SELECT
        payment_id,
        service_id,
        amount,
        LOWER(TRIM(status)) AS payment_status,
        CASE
            WHEN LOWER(TRIM(service_type)) = 'ride'
                 AND COALESCE(payment_correction_flag, FALSE) = TRUE
                THEN 'package'
            ELSE LOWER(TRIM(service_type))
        END AS corrected_service_type
    FROM payment
)

SELECT
    t.trip_id,
    t.source_system,
    t.status AS trip_status,
    p.payment_id,
    p.amount AS payment_amount_eur
FROM trip t
JOIN payment_base p
    ON p.service_id = t.trip_id::TEXT
   AND p.corrected_service_type = 'ride'
WHERE LOWER(TRIM(t.status)) IN (
    'cancelled_by_rider',
    'cancelled_by_driver',
    'aborted',
    'no_show',
    'noshow'
)
AND p.payment_status = 'succeeded'
AND NOT EXISTS (
    SELECT 1
    FROM payment_base r
    WHERE r.service_id = p.service_id
      AND r.corrected_service_type = 'ride'
      AND r.payment_status = 'refunded'
)
ORDER BY
    p.amount DESC,
    t.trip_id ASC
LIMIT 50;

--Q24. Ghost trips audit.

SELECT
    t.trip_id,
    t.source_system,
    t.driver_id,
    t.vehicle_id,
    t.requested_at::DATE AS trip_date
FROM trip t
WHERE LOWER(TRIM(t.status)) IN ('completed', 'finished')
  AND NOT EXISTS (
      SELECT 1
      FROM driver_vehicle_assignment dva
      WHERE dva.driver_id = t.driver_id
        AND dva.vehicle_id = t.vehicle_id
        AND dva.valid_from <= t.requested_at::DATE
        AND (
            dva.valid_to IS NULL
            OR dva.valid_to >= t.requested_at::DATE
        )
  )
ORDER BY
    trip_date DESC,
    t.trip_id ASC
LIMIT 50;

--Q25. Berlin zones by average monthly driver earnings.
WITH ride_revenue AS (
    SELECT
        CASE
            WHEN LOWER(TRIM(z.zone_name)) = 'prenzlauer-berg'
                THEN 'Prenzlauer Berg'
            ELSE TRIM(z.zone_name)
        END AS zone_name_canonical,
        COALESCE(d.merged_into_driver_id, d.driver_id) AS master_driver_id,
        DATE_TRUNC('month', t.requested_at) AS activity_month,
        p.amount
    FROM trip t
    JOIN zone z
        ON t.pickup_zone_id = z.zone_id
    JOIN driver d
        ON t.driver_id = d.driver_id
    JOIN payment p
        ON p.service_id = t.trip_id::TEXT
    WHERE LOWER(TRIM(t.status)) IN ('completed', 'finished')
      AND t.requested_at IS NOT NULL
      AND LOWER(TRIM(p.status)) = 'succeeded'
      AND LOWER(TRIM(p.service_type)) = 'ride'
      AND COALESCE(p.payment_correction_flag, FALSE) = FALSE
),
zone_totals AS (
    SELECT
        zone_name_canonical,
        COUNT(DISTINCT (master_driver_id, activity_month))
            AS qualifying_driver_months,
        SUM(amount) AS total_zone_revenue_eur
    FROM ride_revenue
    GROUP BY zone_name_canonical
)
SELECT
    zone_name_canonical,
    qualifying_driver_months,
    ROUND(total_zone_revenue_eur, 2) AS total_zone_revenue_eur,
    ROUND(
        total_zone_revenue_eur / NULLIF(qualifying_driver_months, 0),
        2
    ) AS avg_revenue_per_driver_per_month_eur
FROM zone_totals
ORDER BY
    avg_revenue_per_driver_per_month_eur DESC,
    zone_name_canonical ASC
LIMIT 25;