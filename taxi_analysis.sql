-- ==============================================================================
-- 🚖 NYC Taxi Trip Data Analysis - SQL Portfolio Project
-- ==============================================================================

-- 1. Trip Distance Segmentation (Quantiles)
-- Business Goal: Divide trips into 3 equal groups (Short, Medium, Long) 
-- to identify the most profitable segment.
WITH distance_quantiles AS (
    SELECT 
        total_amount,
        NTILE(3) OVER (ORDER BY trip_distance) AS distance_group
    FROM trips
    WHERE trip_distance > 0
)
SELECT 
    distance_group,
    SUM(total_amount) AS total_revenue
FROM distance_quantiles
GROUP BY distance_group
ORDER BY total_revenue DESC;


-- 2. Top Pick-up Zones Ranking (Window Functions)
-- Business Goal: Identify TOP 5 pick-up zones within each borough based on 
-- trip volume to optimize the routing of empty taxis.
WITH trips_per_zone AS (
    SELECT 
        COUNT(t.vendorid) AS total_trips,
        z.zone AS pickup_zone,
        z.borough AS borough
    FROM trips t
    LEFT JOIN zones z ON t.pulocationid = z.locationid
    GROUP BY z.borough, z.zone
),
ranked_zones AS (
    SELECT 
        borough,
        pickup_zone,
        total_trips,
        RANK() OVER (PARTITION BY borough ORDER BY total_trips DESC) AS zone_rank
    FROM trips_per_zone
)
SELECT * FROM ranked_zones
WHERE zone_rank <= 5;


-- 3. Day-over-Day Revenue Comparison (LAG)
-- Business Goal: Monitor financial trends by comparing the average 
-- daily trip value with the previous day's value.
WITH daily_avg AS (
    SELECT 
        EXTRACT(DAY FROM tpep_pickup_datetime) AS ride_day,
        AVG(total_amount) AS avg_daily_revenue
    FROM trips
    GROUP BY ride_day
)
SELECT 
    ride_day,
    avg_daily_revenue AS today_avg_revenue,
    LAG(avg_daily_revenue, 1) OVER (ORDER BY ride_day) AS yesterday_avg_revenue
FROM daily_avg;


-- 4. Revenue Structure - Tip Percentage (Ratio)
-- Business Goal: Calculate what percentage of total revenue generated 
-- by each vendor consists of customer tips.
WITH vendor_revenue AS (
    SELECT 
        vendorid,
        SUM(total_amount) AS total_revenue,
        SUM(tip_amount) AS total_tips
    FROM trips
    GROUP BY vendorid
)
SELECT 
    vendorid,
    ROUND((total_tips * 100.0 / total_revenue)::numeric, 2) AS tip_percentage
FROM vendor_revenue;


-- 5. Cumulative Daily Revenue (Running Total)
-- Business Goal: Build a revenue curve for the CFO – a running total 
-- of cash generated day by day over the month.
WITH daily_revenue AS (
    SELECT 
        EXTRACT(DAY FROM tpep_pickup_datetime) AS ride_day,
        SUM(total_amount) AS daily_sum
    FROM trips
    GROUP BY ride_day
)
SELECT 
    ride_day,
    daily_sum,
    SUM(daily_sum) OVER (ORDER BY ride_day) AS cumulative_revenue
FROM daily_revenue;


-- 6. Bottleneck Identification - Airports (CTE & Joins)
-- Business Goal: Detect extreme delays. Find trips originating at airports 
-- that took longer than the average exit time for that specific airport zone.
WITH airport_avg_time AS (
    SELECT 
        z.zone AS airport_zone,
        AVG(EXTRACT(EPOCH FROM (t.tpep_dropoff_datetime - t.tpep_pickup_datetime)) / 60.0) AS avg_duration_minutes
    FROM trips t
    LEFT JOIN zones z ON t.pulocationid = z.locationid
    WHERE z.zone ILIKE '%airport%'
    GROUP BY z.zone
)
SELECT 
    z.zone AS pickup_zone,
    (EXTRACT(EPOCH FROM (t.tpep_dropoff_datetime - t.tpep_pickup_datetime)) / 60.0) AS actual_trip_duration
FROM trips t
LEFT JOIN zones z ON t.pulocationid = z.locationid
LEFT JOIN airport_avg_time aat ON z.zone = aat.airport_zone
WHERE 
    z.zone ILIKE '%airport%' 
    AND (EXTRACT(EPOCH FROM (t.tpep_dropoff_datetime - t.tpep_pickup_datetime)) / 60.0) > aat.avg_duration_minutes;


-- 7. Statistical Analysis: Distance, Fare, and Tip Correlation
-- Business Goal: Examine the Pearson correlation between trip distance, 
-- fare amount, and tipping behavior (excluding unrecorded cash tips).
SELECT 
    ROUND(CAST(CORR(trip_distance, tip_amount) AS NUMERIC), 4) AS distance_tip_correlation,
    ROUND(CAST(CORR(fare_amount, tip_amount) AS NUMERIC), 4) AS fare_tip_correlation,
    ROUND(AVG(tip_amount), 2) AS average_tip,
    ROUND(STDDEV(tip_amount), 2) AS tip_standard_deviation
FROM trips
WHERE 
    tip_amount >= 0 
    AND trip_distance > 0 
    AND payment_type = 'Credit Card';
