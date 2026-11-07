CREATE SCHEMA IF NOT EXISTS emergency_ops OPTIONS(location='US');

-- Hazard Perimeters Table
CREATE TABLE IF NOT EXISTS emergency_ops.hazard_perimeter_data (
    hazard_id STRING,
    zone_name STRING,
    perimeter_polygon GEOGRAPHY,
    severity_score FLOAT64,
    status STRING,
    timestamp TIMESTAMP
);

-- Road Network Graph Table
CREATE TABLE IF NOT EXISTS emergency_ops.road_network_graph (
    segment_id STRING,
    corridor_name STRING,
    route_geom GEOGRAPHY,
    is_blocked BOOL,
    current_congestion_index FLOAT64
);

-- Training Data for Shelter Occupancy Forecast (BQML)
CREATE OR REPLACE TABLE emergency_ops.shelter_historical_influx (
    shelter_id STRING,
    lead_time_hours INT64,
    historical_evacuee_count INT64,
    weather_severity_index FLOAT64,
    capacity_exceeded INT64
);

-- Insert seed data into the historical influx table
INSERT INTO emergency_ops.shelter_historical_influx (shelter_id, lead_time_hours, historical_evacuee_count, weather_severity_index, capacity_exceeded)
VALUES
    ('SHELTER-01', 12, 450, 8.5, 0),
    ('SHELTER-01', 6, 850, 9.2, 1),
    ('SHELTER-02', 24, 200, 5.0, 0),
    ('SHELTER-02', 4, 920, 9.8, 1),
    ('SHELTER-03', 18, 600, 7.1, 0);

-- Train BQML Logistic Regression Model to predict shelter capacity breaches
CREATE OR REPLACE MODEL emergency_ops.shelter_occupancy_forecast_model
OPTIONS(
    model_type='logistic_reg',
    input_label_cols=['capacity_exceeded']
) AS
SELECT
    lead_time_hours,
    historical_evacuee_count,
    weather_severity_index,
    capacity_exceeded
FROM
    emergency_ops.shelter_historical_influx;
