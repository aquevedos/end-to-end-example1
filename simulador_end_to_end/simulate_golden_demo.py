#!/usr/bin/env python3
"""
Simulador End-to-End de Google Cloud Data Analytics Golden Demo.
Recrea todas las capas de la arquitectura Medallion (Raw -> Enriched -> Curated),
Gobernanza IAM/RLS/Data Masking, Multi-Cloud Omni (AWS S3 / Azure ADLS),
Apache Iceberg, Unstructured Vision AI, Gemini 2.5 Flash LLM & Embeddings,
BQML High-Value Ride Prediction, Datastream CDC, Dataflow Streaming y Dataplex Data Quality.
"""

import csv
import datetime
import hashlib
import json
import math
import os
import random
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Tuple

# Semilla determinista para reproducibilidad arquitectónica
random.seed(42)

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "datos_simulados"
DB_PATH = BASE_DIR / "golden_demo_simulated.db"
REPORT_JSON_PATH = BASE_DIR / "simulation_results.json"


def mask_credit_card(cc_number: str) -> str:
    """Enmascara PII dejando únicamente los últimos 4 dígitos visibles."""
    clean = cc_number.replace("-", "").strip()
    if len(clean) >= 4:
        return f"****-****-****-{clean[-4:]}"
    return "****-****-****-0000"


def crypto_shred_aead(plaintext: str, user_key_active: bool = True) -> str:
    """Simula cifrado AEAD.ENCRYPT de BigQuery y Crypto-Shredding cuando se destruye la llave KMS."""
    if not user_key_active:
        return "[CRYPTO_SHREDDED_KEY_DESTROYED]"
    digest = hashlib.sha256(plaintext.encode("utf-8")).hexdigest()[:24]
    return f"AEAD_CIPHERTEXT({digest})"


def cosine_similarity(vec_a: List[float], vec_b: List[float]) -> float:
    """Calcula similitud coseno entre dos embeddings de 8 dimensiones."""
    dot = sum(a * b for a, b in zip(vec_a, vec_b))
    norm_a = math.sqrt(sum(a * a for a in vec_a))
    norm_b = math.sqrt(sum(b * b for b in vec_b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return round(dot / (norm_a * norm_b), 4)


def init_directories() -> None:
    """Crea la estructura de directorios para los datos simulados."""
    for zone in ["01_raw_zone", "02_enriched_zone", "03_curated_zone", "04_dataplex_governance"]:
        (DATA_DIR / zone).mkdir(parents=True, exist_ok=True)


def create_schema(conn: sqlite3.Connection) -> None:
    """Crea el esquema relacional y analítico que emula los datasets de BigQuery del Golden Demo."""
    cursor = conn.cursor()

    # 1. RAW ZONE TABLES
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS raw_biglake_rideshare_zone (
            location_id INTEGER PRIMARY KEY,
            borough TEXT NOT NULL,
            zone TEXT NOT NULL,
            service_zone TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS raw_aws_omni_s3_rides (
            omni_ride_id TEXT PRIMARY KEY,
            cloud_provider TEXT NOT NULL,
            s3_bucket_uri TEXT NOT NULL,
            pickup_date TEXT NOT NULL,
            pickup_location_id INTEGER NOT NULL,
            dropoff_location_id INTEGER NOT NULL,
            passenger_count INTEGER NOT NULL,
            tip_amount REAL NOT NULL,
            total_amount REAL NOT NULL,
            year INTEGER NOT NULL,
            month INTEGER NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS raw_biglake_object_images (
            uri TEXT PRIMARY KEY,
            content_type TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            updated_time TEXT NOT NULL,
            location_id INTEGER NOT NULL,
            camera_metadata_json TEXT NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS raw_datastream_postgres_cdc (
            cdc_event_id TEXT PRIMARY KEY,
            source_table TEXT NOT NULL,
            op_type TEXT NOT NULL,
            lsn_sequence TEXT NOT NULL,
            trip_id INTEGER NOT NULL,
            driver_id INTEGER NOT NULL,
            fare_amount REAL NOT NULL,
            private_psc_ip TEXT NOT NULL,
            event_timestamp TEXT NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS raw_dataflow_streaming_events (
            stream_msg_id TEXT PRIMARY KEY,
            pubsub_topic TEXT NOT NULL,
            taxi_type TEXT NOT NULL,
            vendor_id INTEGER NOT NULL,
            pickup_location_id INTEGER NOT NULL,
            passenger_count INTEGER NOT NULL,
            meter_reading REAL NOT NULL,
            processing_latency_ms INTEGER NOT NULL,
            ingest_timestamp TEXT NOT NULL
        )
    """)

    # 2. ENRICHED ZONE TABLES (Iceberg + Vision AI + Gemini Enriched)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS enriched_iceberg_payment_type (
            payment_type_id INTEGER PRIMARY KEY,
            payment_type_description TEXT NOT NULL,
            iceberg_snapshot_id TEXT NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS enriched_iceberg_rideshare_trip (
            rideshare_trip_id TEXT PRIMARY KEY,
            pickup_location_id INTEGER NOT NULL,
            pickup_datetime TEXT NOT NULL,
            dropoff_location_id INTEGER NOT NULL,
            dropoff_datetime TEXT NOT NULL,
            ride_distance REAL NOT NULL,
            is_airport INTEGER NOT NULL,
            payment_type_id INTEGER NOT NULL,
            fare_amount REAL NOT NULL,
            tip_amount REAL NOT NULL,
            taxes_amount REAL NOT NULL,
            total_amount REAL NOT NULL,
            credit_card_masked TEXT NOT NULL,
            credit_card_aead_cipher TEXT NOT NULL,
            partition_date TEXT NOT NULL,
            iceberg_table_format TEXT NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS enriched_vision_ai_images_score (
            uri TEXT PRIMARY KEY,
            location_id INTEGER NOT NULL,
            image_date TEXT NOT NULL,
            detected_object TEXT NOT NULL,
            object_confidence REAL NOT NULL,
            detected_landmark TEXT NOT NULL,
            landmark_confidence REAL NOT NULL,
            safety_status TEXT NOT NULL
        )
    """)

    # 3. CURATED ZONE TABLES (Rideshare Plus AI Lakehouse + Gemini LLM + BQML)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS curated_llm_customer (
            customer_id INTEGER PRIMARY KEY,
            customer_name TEXT NOT NULL,
            customer_since_date TEXT NOT NULL,
            customer_attribute_summary TEXT NOT NULL,
            customer_review_summary TEXT NOT NULL,
            customer_quantitative_analysis TEXT NOT NULL,
            total_trip_count INTEGER NOT NULL,
            avg_trip_distance REAL NOT NULL,
            avg_fare_amount REAL NOT NULL,
            avg_tip_amount REAL NOT NULL,
            sum_total_amount REAL NOT NULL,
            embedding_json TEXT NOT NULL,
            preferred_drivers_json TEXT NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS curated_llm_driver (
            driver_id INTEGER PRIMARY KEY,
            driver_name TEXT NOT NULL,
            driver_since_date TEXT NOT NULL,
            driver_attribute_summary TEXT NOT NULL,
            driver_review_summary TEXT NOT NULL,
            driver_quantitative_analysis TEXT NOT NULL,
            total_trip_count INTEGER NOT NULL,
            avg_rating REAL NOT NULL,
            avg_tip_amount REAL NOT NULL,
            sum_total_amount REAL NOT NULL,
            embedding_json TEXT NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS curated_llm_customer_review (
            review_id INTEGER PRIMARY KEY,
            trip_id TEXT NOT NULL,
            customer_id INTEGER NOT NULL,
            customer_name TEXT NOT NULL,
            driver_id INTEGER NOT NULL,
            driver_name TEXT NOT NULL,
            review_date TEXT NOT NULL,
            customer_review_text TEXT NOT NULL,
            review_sentiment TEXT NOT NULL,
            extracted_driver_theme TEXT NOT NULL,
            extracted_customer_theme TEXT NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS curated_bqml_predict_high_value_rides (
            prediction_id INTEGER PRIMARY KEY,
            location_id INTEGER NOT NULL,
            borough TEXT NOT NULL,
            zone TEXT NOT NULL,
            pickup_day_of_week TEXT NOT NULL,
            pickup_hour INTEGER NOT NULL,
            ride_distance REAL NOT NULL,
            is_raining INTEGER NOT NULL,
            is_snowing INTEGER NOT NULL,
            people_traveling_cnt INTEGER NOT NULL,
            is_high_value_ride INTEGER NOT NULL,
            predicted_probability REAL NOT NULL,
            recommended_action TEXT NOT NULL,
            execution_date TEXT NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS curated_dataplex_data_quality (
            dq_check_id TEXT PRIMARY KEY,
            target_dataset TEXT NOT NULL,
            target_table TEXT NOT NULL,
            column_name TEXT NOT NULL,
            rule_type TEXT NOT NULL,
            rule_expression TEXT NOT NULL,
            evaluated_rows INTEGER NOT NULL,
            passed_rows INTEGER NOT NULL,
            pass_rate_pct REAL NOT NULL,
            dq_status TEXT NOT NULL
        )
    """)

    conn.commit()


def populate_raw_zone(conn: sqlite3.Connection) -> Dict[str, Any]:
    """Simula la ingesta en la Zona Raw: BigLake Zones, AWS/Azure Omni, Object Tables, Datastream CDC y Dataflow."""
    cursor = conn.cursor()

    # 1. NYC Taxi / Rideshare Zones (Coordenadas reales del script sp_process_data.sql)
    zones_data = [
        (1, "EWR", "Newark Airport", "EWR", 40.689529, -74.174461),
        (4, "Manhattan", "Alphabet City", "Yellow Zone", 40.726184, -73.978886),
        (12, "Manhattan", "Battery Park", "Yellow Zone", 40.702715, -74.015806),
        (13, "Manhattan", "Battery Park City", "Yellow Zone", 40.710067, -74.016367),
        (24, "Manhattan", "Bloomingdale", "Yellow Zone", 40.798822, -73.973244),
        (43, "Manhattan", "Central Park", "Yellow Zone", 40.794320, -73.954808),
        (48, "Manhattan", "Clinton East", "Yellow Zone", 40.735480, -73.990616),
        (68, "Manhattan", "East Chelsea", "Yellow Zone", 40.742418, -74.005537),
        (79, "Manhattan", "East Village", "Yellow Zone", 40.727620, -73.985930),
        (132, "Queens", "JFK Airport", "Airports", 40.641311, -73.778139),
        (138, "Queens", "LaGuardia Airport", "Airports", 40.776927, -73.873966),
        (161, "Manhattan", "Midtown Center", "Yellow Zone", 40.758000, -73.985500),
        (162, "Manhattan", "Midtown East", "Yellow Zone", 40.754931, -73.971834),
        (186, "Manhattan", "Penn Station/Madison Sq West", "Yellow Zone", 40.750568, -73.993519),
        (230, "Manhattan", "Times Sq/Theatre District", "Yellow Zone", 40.758896, -73.985130),
        (237, "Manhattan", "Upper East Side South", "Yellow Zone", 40.768500, -73.964700),
        (33, "Brooklyn", "Brooklyn Heights", "Boro Zone", 40.696455, -73.998299),
        (61, "Brooklyn", "Crown Heights North", "Boro Zone", 40.674118, -73.954691),
        (18, "Bronx", "Bedford Park", "Boro Zone", 40.872134, -73.887864),
        (5, "Staten Island", "Arden Heights", "Boro Zone", 40.554598, -74.185205),
    ]
    cursor.executemany(
        """
        INSERT OR REPLACE INTO raw_biglake_rideshare_zone
        (location_id, borough, zone, service_zone, latitude, longitude)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        zones_data,
    )

    # Exportar CSV de zonas en 01_raw_zone
    with open(DATA_DIR / "01_raw_zone" / "biglake_rideshare_zone.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["location_id", "borough", "zone", "service_zone", "latitude", "longitude"])
        writer.writerows(zones_data)

    # 2. BigQuery Omni Multi-Cloud (AWS S3 & Azure ADLS Federated Queries)
    omni_rows = []
    zone_ids = [z[0] for z in zones_data]
    for i in range(1, 61):
        cloud = "AWS_S3_OMNI" if i <= 40 else "AZURE_ADLS_OMNI"
        uri = (
            f"s3://gcp-analytics-omni-bucket/taxi-data/yellow/trips_table/parquet/year=2026/month=11/part-{i:04d}.parquet"
            if cloud == "AWS_S3_OMNI"
            else f"azure://gcpanalyticsadls.blob.core.windows.net/taxi-data/yellow/part-{i:04d}.parquet"
        )
        pu_loc = random.choice(zone_ids)
        do_loc = random.choice(zone_ids)
        passengers = random.randint(1, 4)
        tip = round(random.uniform(2.5, 18.0), 2)
        total = round(random.uniform(18.0, 95.0) + tip, 2)
        omni_rows.append(
            (
                f"OMNI-{2026}-{i:04d}",
                cloud,
                uri,
                f"2026-11-{random.randint(1, 28):02d}",
                pu_loc,
                do_loc,
                passengers,
                tip,
                total,
                2026,
                11,
            )
        )

    cursor.executemany(
        """
        INSERT OR REPLACE INTO raw_aws_omni_s3_rides
        (omni_ride_id, cloud_provider, s3_bucket_uri, pickup_date, pickup_location_id,
         dropoff_location_id, passenger_count, tip_amount, total_amount, year, month)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        omni_rows,
    )

    # 3. BigLake Unstructured Data Object Table (Imágenes en GCS)
    image_scenarios = [
        ("rideshare_cam_001.jpg", 230, "Times Square Intersection", "Vehicle/Taxi Fleet", "Landmark: Times Square"),
        ("rideshare_cam_002.jpg", 132, "JFK Terminal 4 Curbside", "Luggage & Passenger Queue", "Landmark: JFK Airport"),
        ("rideshare_cam_003.jpg", 43, "Central Park South Entrance", "Pedestrian & Bicycle", "Landmark: Central Park"),
        ("rideshare_cam_004.jpg", 186, "Penn Station 8th Ave", "High Crowd Density", "Landmark: Madison Square Garden"),
        ("rideshare_cam_005.jpg", 12, "Battery Park Ferry Terminal", "Rainy Street Reflection", "Landmark: Statue of Liberty View"),
        ("rideshare_cam_006.jpg", 161, "Midtown 5th Avenue", "Executive Black SUV", "Landmark: Rockefeller Center"),
        ("rideshare_cam_007.jpg", 138, "LaGuardia Terminal B", "Airport Shuttle Lane", "Landmark: LaGuardia Airport"),
        ("rideshare_cam_008.jpg", 33, "Brooklyn Promenade", "Evening Rush Traffic", "Landmark: Brooklyn Bridge"),
    ]
    object_rows = []
    for idx, (fname, loc_id, scene, obj_type, landmark) in enumerate(image_scenarios, start=1):
        uri = f"gs://rideshare-lakehouse-raw-bucket/rideshare_images/{fname}"
        meta = json.dumps({
            "camera_id": f"CAM-NYC-{idx:03d}",
            "scene_context": scene,
            "resolution": "3840x2160",
            "weather_sensor": "Rain" if idx % 3 == 0 else "Clear",
            "expected_object": obj_type,
            "expected_landmark": landmark,
        })
        object_rows.append((uri, "image/jpeg", random.randint(1450000, 4200000), f"2026-11-02T1{idx}:15:00Z", loc_id, meta))

    cursor.executemany(
        """
        INSERT OR REPLACE INTO raw_biglake_object_images
        (uri, content_type, size_bytes, updated_time, location_id, camera_metadata_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        object_rows,
    )

    # 4. Datastream CDC (Cloud SQL PostgreSQL -> BigQuery over Private Service Connect)
    cdc_ops = ["INSERT", "INSERT", "UPDATE", "INSERT", "UPDATE", "INSERT", "DELETE", "INSERT"]
    cdc_rows = []
    for i in range(1, 25):
        op = cdc_ops[i % len(cdc_ops)]
        cdc_rows.append(
            (
                f"CDC-LSN-{100000 + i}",
                "public.rideshare_live_ledger",
                op,
                f"0/16B37{i:02X}",
                5000 + i,
                100 + (i % 8),
                round(random.uniform(15.0, 82.0), 2),
                "10.240.0.14 (PSC-Private-Endpoint)",
                f"2026-11-02T17:{30 + (i % 29):02d}:{i:02d}Z",
            )
        )
    cursor.executemany(
        """
        INSERT OR REPLACE INTO raw_datastream_postgres_cdc
        (cdc_event_id, source_table, op_type, lsn_sequence, trip_id, driver_id, fare_amount, private_psc_ip, event_timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        cdc_rows,
    )

    # 5. Dataflow Streaming Ingestion (Pub/Sub `taxirides-realtime` -> BigQuery Storage Write API)
    stream_rows = []
    for i in range(1, 31):
        stream_rows.append(
            (
                f"PUBSUB-MSG-{90000 + i}",
                "projects/pubsub-public-data/topics/taxirides-realtime",
                "Yellow_Rideshare" if i % 2 == 0 else "Green_Rideshare",
                1 if i % 2 == 0 else 2,
                random.choice(zone_ids),
                random.randint(1, 4),
                round(random.uniform(12.4, 68.9), 2),
                random.randint(18, 95),
                f"2026-11-02T17:55:{i % 60:02d}Z",
            )
        )
    cursor.executemany(
        """
        INSERT OR REPLACE INTO raw_dataflow_streaming_events
        (stream_msg_id, pubsub_topic, taxi_type, vendor_id, pickup_location_id,
         passenger_count, meter_reading, processing_latency_ms, ingest_timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        stream_rows,
    )

    conn.commit()
    return {
        "zones_loaded": len(zones_data),
        "omni_multicloud_records": len(omni_rows),
        "unstructured_object_images": len(object_rows),
        "datastream_cdc_events": len(cdc_rows),
        "dataflow_streaming_messages": len(stream_rows),
    }


def populate_enriched_zone(conn: sqlite3.Connection) -> Dict[str, Any]:
    """Simula la Zona Enriched: Transformaciones BigSpark + Apache Iceberg y Cloud Vision AI sobre Object Tables."""
    cursor = conn.cursor()

    # 1. Apache Iceberg Payment Types (sp_iceberg_spark_transformation.py)
    payment_types = [
        (1, "Credit Card (Contactless / NFC)", "iceberg-snap-8849201920"),
        (2, "Cash", "iceberg-snap-8849201920"),
        (3, "Google Pay / Digital Wallet", "iceberg-snap-8849201921"),
        (4, "Corporate Account Billing", "iceberg-snap-8849201921"),
    ]
    cursor.executemany(
        """
        INSERT OR REPLACE INTO enriched_iceberg_payment_type
        (payment_type_id, payment_type_description, iceberg_snapshot_id)
        VALUES (?, ?, ?)
        """,
        payment_types,
    )

    # 2. Apache Iceberg Rideshare Trips con PII Enmascarado + AEAD Encryption
    cursor.execute("SELECT location_id FROM raw_biglake_rideshare_zone")
    zone_ids = [r[0] for r in cursor.fetchall()]

    trips_iceberg = []
    # Incluimos la tarjeta específica que busca el script sp_demo_script.sql (enmascarada según políticas de seguridad)
    for i in range(1, 121):
        trip_id = f"TRIP-ICEBERG-2026-{i:04d}"
        pu_loc = random.choice(zone_ids)
        do_loc = random.choice(zone_ids)
        is_airport = 1 if pu_loc in (1, 132, 138) or do_loc in (1, 132, 138) else 0
        dist = round(random.uniform(8.5, 22.4) if is_airport else random.uniform(1.1, 9.8), 2)
        fare = round(dist * 3.85 + (15.0 if is_airport else 4.5), 2)
        tip = round(fare * random.uniform(0.15, 0.28), 2)
        taxes = round(fare * 0.08875, 2)
        total = round(fare + tip + taxes, 2)
        raw_cc = "6701-1287-5578-5710" if i == 1 else f"4532-{random.randint(1000,9999)}-{random.randint(1000,9999)}-{random.randint(1000,9999)}"
        masked_cc = mask_credit_card(raw_cc)
        aead_cipher = crypto_shred_aead(raw_cc, user_key_active=(i != 120))  # El registro 120 demuestra Crypto-Shredding
        hour = random.randint(6, 23)
        pu_dt = f"2026-11-02T{hour:02d}:10:00"
        do_dt = f"2026-11-02T{hour:02d}:42:00"

        trips_iceberg.append(
            (
                trip_id,
                pu_loc,
                pu_dt,
                do_loc,
                do_dt,
                dist,
                is_airport,
                random.choice([1, 1, 3, 2, 4]),
                fare,
                tip,
                taxes,
                total,
                masked_cc,
                aead_cipher,
                "2026-11-02",
                "Apache Iceberg v2 (BigLake Metastore)",
            )
        )

    cursor.executemany(
        """
        INSERT OR REPLACE INTO enriched_iceberg_rideshare_trip
        (rideshare_trip_id, pickup_location_id, pickup_datetime, dropoff_location_id,
         dropoff_datetime, ride_distance, is_airport, payment_type_id, fare_amount,
         tip_amount, taxes_amount, total_amount, credit_card_masked, credit_card_aead_cipher,
         partition_date, iceberg_table_format)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        trips_iceberg,
    )

    # 3. Vision AI Object Detection sobre Object Tables (sp_process_data.sql)
    cursor.execute("SELECT uri, location_id, camera_metadata_json FROM raw_biglake_object_images")
    vision_rows = []
    for uri, loc_id, meta_str in cursor.fetchall():
        meta = json.loads(meta_str)
        vision_rows.append(
            (
                uri,
                loc_id,
                "2026-11-02",
                meta["expected_object"],
                round(random.uniform(0.92, 0.99), 4),
                meta["expected_landmark"],
                round(random.uniform(0.89, 0.98), 4),
                "SAFE_TRAFFIC_FLOW",
            )
        )

    cursor.executemany(
        """
        INSERT OR REPLACE INTO enriched_vision_ai_images_score
        (uri, location_id, image_date, detected_object, object_confidence,
         detected_landmark, landmark_confidence, safety_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        vision_rows,
    )

    conn.commit()
    return {
        "iceberg_payment_types": len(payment_types),
        "iceberg_enriched_trips": len(trips_iceberg),
        "vision_ai_scored_images": len(vision_rows),
    }


def populate_curated_zone(conn: sqlite3.Connection) -> Dict[str, Any]:
    """Simula la Zona Curated: Gemini 2.5 Flash LLM Reviews, Vector Embeddings (text-embedding-005), BQML y Dataplex."""
    cursor = conn.cursor()

    # 1. Conductores (Drivers) con perfiles generados por Gemini 2.5 Flash y vectores text-embedding-005
    drivers_catalog = [
        (
            101,
            "Carlos Mendoza",
            "2021-03-14",
            "Conductor ejecutivo bilingüe; vehículo eléctrico impecable, climatización fresca (68°F) y conducción suave.",
            "96% reseñas positivas. Los pasajeros destacan puntualidad en rutas hacia JFK/LaGuardia y silencio respetuoso.",
            "Realiza promedio de 42 viajes/semana, ticket medio de $64.20 y propina promedio superior al 22%.",
            184,
            4.95,
            12.40,
            11812.80,
            [0.92, 0.85, 0.15, 0.90, 0.88, 0.20, 0.75, 0.91],  # Perfil Ejecutivo / Silencioso / Aeropuerto
        ),
        (
            102,
            "Elena Rostova",
            "2022-07-01",
            "Especialista en rutas nocturnas y Midtown; ofrece cargadores USB-C, agua embotellada y música jazz suave.",
            "94% reseñas positivas. Muy valorada por ejecutivos de finanzas y turistas en Times Square.",
            "Alta eficiencia en horas pico (17:00-21:00), distancia media 6.8 millas, excelente retención.",
            156,
            4.91,
            10.85,
            9420.50,
            [0.88, 0.90, 0.25, 0.84, 0.92, 0.30, 0.80, 0.87],  # Perfil Ejecutivo / Jazz / Confort
        ),
        (
            103,
            "Marcus Vance",
            "2020-11-19",
            "Conductor conversador y conocedor gastronómico de NYC; SUV amplia ideal para grupos y familias con equipaje.",
            "91% reseñas positivas. Excelente trato con familias y traslados grupales desde Penn Station.",
            "Vehículo de alta capacidad (hasta 6 pasajeros), distancia media 9.4 millas.",
            210,
            4.87,
            11.10,
            13540.00,
            [0.35, 0.40, 0.95, 0.89, 0.45, 0.92, 0.88, 0.40],  # Perfil Conversador / Familiar / SUV Amplia
        ),
        (
            104,
            "Aisha Patel",
            "2023-01-10",
            "Conducción ecológica ultra segura, experta en evitar congestión en Manhattan y Brooklyn Heights.",
            "95% reseñas positivas. Destacada por rapidez, limpieza extrema y trato cortés.",
            "Tiempo de espera promedio menor a 3 minutos, alta puntuación en seguridad vial.",
            132,
            4.93,
            9.95,
            7890.40,
            [0.85, 0.82, 0.30, 0.78, 0.86, 0.35, 0.92, 0.89],  # Perfil Rápido / Silencioso / Eco
        ),
        (
            105,
            "Devon Brooks",
            "2022-05-22",
            "Conducción rápida pero en ocasiones frena bruscamente; música urbana a volumen moderado.",
            "72% reseñas positivas, 18% neutrales, 10% negativas por temperatura cálida en cabina.",
            "Volumen alto de viajes cortos en East Village y Soho.",
            145,
            4.42,
            5.60,
            5840.20,
            [0.20, 0.30, 0.80, 0.35, 0.25, 0.75, 0.40, 0.22],  # Perfil Viajes Cortos / Música / Dinámico
        ),
    ]

    for d in drivers_catalog:
        cursor.execute(
            """
            INSERT OR REPLACE INTO curated_llm_driver
            (driver_id, driver_name, driver_since_date, driver_attribute_summary,
             driver_review_summary, driver_quantitative_analysis, total_trip_count,
             avg_rating, avg_tip_amount, sum_total_amount, embedding_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], json.dumps(d[10])),
        )

    # 2. Clientes (Customers) con perfiles enriquecidos por Gemini 2.5 Flash y emparejamiento vectorial (`VECTOR_SEARCH`)
    customers_catalog = [
        (
            201,
            "Sofía Valdés",
            "2022-02-10",
            "Prefiere vehículos silenciosos para tomar llamadas ejecutivas, aire acondicionado fresco y rutas directas a aeropuertos.",
            "Valora la puntualidad extrema, limpieza interior y conductores que respetan el espacio de trabajo.",
            "Viaja 4 veces por semana entre Midtown East y JFK/LaGuardia; propina media del 24% ($14.50).",
            68,
            11.4,
            52.80,
            14.50,
            4576.40,
            [0.94, 0.87, 0.12, 0.91, 0.89, 0.18, 0.78, 0.93],
        ),
        (
            202,
            "Liam O'Connor",
            "2021-09-05",
            "Viaja en familia con niños y equipaje; prefiere SUV espaciosa, conversación amena y recomendaciones locales.",
            "Deja reseñas entusiastas cuando el conductor ayuda con las maletas y mantiene un ambiente cálido.",
            "Viajes de fin de semana y traslados desde Penn Station hacia hoteles en Central Park.",
            42,
            8.2,
            44.10,
            10.20,
            2280.60,
            [0.32, 0.38, 0.94, 0.91, 0.42, 0.95, 0.85, 0.38],
        ),
        (
            203,
            "Dr. Kenji Takahashi",
            "2023-04-18",
            "Prioriza seguridad vial, conducción ecológica sin frenazos, música jazz instrumental o silencio.",
            "Muy analítico en sus reseñas; premia la cortesía y la eficiencia en rutas por Upper East Side.",
            "Frecuencia diaria de lunes a viernes, distancia media de 5.6 millas, propina constante del 20%.",
            95,
            5.6,
            31.40,
            6.80,
            3629.00,
            [0.87, 0.88, 0.22, 0.82, 0.91, 0.28, 0.89, 0.88],
        ),
        (
            204,
            "Camila Restrepo",
            "2023-08-29",
            "Usuaria frecuente en horas pico vespertinas; requiere cargador USB-C y rutas ágiles hacia Brooklyn Heights.",
            "Aprecia vehículos modernos, olor agradable y conductores que conocen atajos ante tráfico pesado.",
            "38 viajes registrados, gasto acumulado de $1,640.50, alta sensibilidad a tiempos de espera.",
            38,
            6.3,
            34.90,
            8.27,
            1640.50,
            [0.84, 0.83, 0.29, 0.79, 0.87, 0.33, 0.90, 0.86],
        ),
    ]

    for c in customers_catalog:
        c_vec = c[11]
        # Calcular similitud coseno contra todos los conductores (emulando VECTOR_SEARCH en BigQuery)
        ranked_drivers = sorted(
            [
                {
                    "driver_id": d[0],
                    "driver_name": d[1],
                    "similarity_score": cosine_similarity(c_vec, d[10]),
                }
                for d in drivers_catalog
            ],
            key=lambda x: x["similarity_score"],
            reverse=True,
        )[:2]

        cursor.execute(
            """
            INSERT OR REPLACE INTO curated_llm_customer
            (customer_id, customer_name, customer_since_date, customer_attribute_summary,
             customer_review_summary, customer_quantitative_analysis, total_trip_count,
             avg_trip_distance, avg_fare_amount, avg_tip_amount, sum_total_amount,
             embedding_json, preferred_drivers_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                c[0],
                c[1],
                c[2],
                c[3],
                c[4],
                c[5],
                c[6],
                c[7],
                c[8],
                c[9],
                c[10],
                json.dumps(c_vec),
                json.dumps(ranked_drivers),
            ),
        )

    # 3. Reseñas de Clientes analizadas por Gemini 2.5 Flash (Sentiment + Driver/Customer Themes)
    reviews_data = [
        (
            1,
            "TRIP-ICEBERG-2026-0001",
            201,
            "Sofía Valdés",
            101,
            "Carlos Mendoza",
            "2026-11-01",
            "Carlos arrived 4 minutes early for my 6 AM flight to JFK. The Tesla cabin was spotless, cool at 68 degrees, and completely quiet so I could finish my board call.",
            "Positive",
            "Punctual, Spotless EV, Quiet Cabin, Cool AC (68°F), Smooth Airport Transfer",
            "Business Executive, Prefers Quiet Ride, Early Morning Airport Traveler",
        ),
        (
            2,
            "TRIP-ICEBERG-2026-0002",
            202,
            "Liam O'Connor",
            103,
            "Marcus Vance",
            "2026-11-01",
            "Marcus was fantastic with our two kids! Huge SUV that fit all four suitcases easily, and he gave us great pizza recommendations near Central Park.",
            "Positive",
            "Large SUV Capacity, Family Friendly, Helpful with Luggage, Local Expert",
            "Family Traveler, Heavy Luggage, Enjoys Friendly Conversation",
        ),
        (
            3,
            "TRIP-ICEBERG-2026-0003",
            203,
            "Dr. Kenji Takahashi",
            102,
            "Elena Rostova",
            "2026-11-01",
            "Very relaxing evening commute from Midtown East. Elena played soft jazz, drove smoothly without any harsh braking, and offered bottled water.",
            "Positive",
            "Smooth Driving, Soft Jazz Music, Complimentary Water, Courteous",
            "Values Safety, Prefers Calm Atmosphere, Evening Commuter",
        ),
        (
            4,
            "TRIP-ICEBERG-2026-0004",
            204,
            "Camila Restrepo",
            104,
            "Aisha Patel",
            "2026-11-02",
            "Aisha avoided a massive traffic jam on the Brooklyn Bridge and had a fast USB-C charger ready in the backseat. Super clean car!",
            "Positive",
            "Proactive Route Navigation, USB-C Charger Available, High Cleanliness",
            "Tech-Savvy Commuter, Time-Sensitive, Values Amenities",
        ),
        (
            5,
            "TRIP-ICEBERG-2026-0005",
            201,
            "Sofía Valdés",
            105,
            "Devon Brooks",
            "2026-11-02",
            "We got there on time, but the car was a bit warm and the driver braked hard twice in Midtown traffic while I was reading emails.",
            "Negative",
            "Harsh Braking, Warm Cabin Temperature, Fast Pace",
            "Sensitive to Motion Sickness, Requires Smooth & Cool Ride",
        ),
    ]

    cursor.executemany(
        """
        INSERT OR REPLACE INTO curated_llm_customer_review
        (review_id, trip_id, customer_id, customer_name, driver_id, driver_name,
         review_date, customer_review_text, review_sentiment, extracted_driver_theme, extracted_customer_theme)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        reviews_data,
    )

    # 4. BQML High-Value Ride Predictions (sp_model_training.sql & sp_website_score_data.sql)
    bqml_predictions = [
        (1, 132, "Queens", "JFK Airport", "Monday", 18, 16.8, 1, 0, 142, 1, 0.964, "DESPACHAR PRIORIDAD: Alta demanda ejecutiva + lluvia en Terminal 4", "2026-11-02T18:00:00Z"),
        (2, 230, "Manhattan", "Times Sq/Theatre District", "Monday", 18, 7.4, 1, 0, 118, 1, 0.928, "POSICIONAR FLOTA: Salida de teatros y oficinas con tarifa dinámica", "2026-11-02T18:00:00Z"),
        (3, 161, "Manhattan", "Midtown Center", "Monday", 18, 9.1, 1, 0, 96, 1, 0.895, "ALTA RENTABILIDAD: Viajes corporativos hacia aeropuertos y Brooklyn", "2026-11-02T18:00:00Z"),
        (4, 138, "Queens", "LaGuardia Airport", "Monday", 18, 11.2, 1, 0, 88, 1, 0.872, "DESPACHAR PRIORIDAD: Llegadas de vuelos nacionales vespertinos", "2026-11-02T18:00:00Z"),
        (5, 186, "Manhattan", "Penn Station/Madison Sq West", "Monday", 18, 5.8, 0, 0, 74, 1, 0.784, "DEMANDA SOSTENIDA: Conexión ferroviaria regional", "2026-11-02T18:00:00Z"),
        (6, 33, "Brooklyn", "Brooklyn Heights", "Monday", 18, 4.9, 0, 0, 41, 0, 0.412, "FLUJO ESTÁNDAR: Mantener unidades locales sin recargo", "2026-11-02T18:00:00Z"),
        (7, 5, "Staten Island", "Arden Heights", "Monday", 18, 3.2, 0, 0, 12, 0, 0.145, "BAJA DEMANDA: Reubicar conductores hacia Manhattan Sur", "2026-11-02T18:00:00Z"),
    ]

    cursor.executemany(
        """
        INSERT OR REPLACE INTO curated_bqml_predict_high_value_rides
        (prediction_id, location_id, borough, zone, pickup_day_of_week, pickup_hour,
         ride_distance, is_raining, is_snowing, people_traveling_cnt, is_high_value_ride,
         predicted_probability, recommended_action, execution_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        bqml_predictions,
    )

    # 5. Dataplex Data Quality Checks (sample-dataplex-run-data-quality.py)
    dq_checks = [
        ("DQ-001", "rideshare_lakehouse_curated", "bigquery_rideshare_trip", "rideshare_trip_id", "NOT_NULL & UNIQUE", "rideshare_trip_id IS NOT NULL", 120, 120, 100.0, "PASSED"),
        ("DQ-002", "rideshare_lakehouse_curated", "bigquery_rideshare_trip", "total_amount", "VALUE_RANGE", "total_amount > 0 AND total_amount < 1500", 120, 120, 100.0, "PASSED"),
        ("DQ-003", "rideshare_lakehouse_curated", "bigquery_rideshare_trip", "pickup_location_id", "REFERENTIAL_INTEGRITY", "pickup_location_id IN (SELECT location_id FROM bigquery_rideshare_zone)", 120, 120, 100.0, "PASSED"),
        ("DQ-004", "rideshare_llm_curated", "customer_review", "review_sentiment", "ALLOWED_VALUES", "review_sentiment IN ('Positive', 'Neutral', 'Negative')", 5, 5, 100.0, "PASSED"),
        ("DQ-005", "rideshare_lakehouse_curated", "bigquery_rideshare_trip", "credit_card_masked", "PII_MASKING_POLICY", "STARTS_WITH(credit_card_masked, '****-****-****-')", 120, 120, 100.0, "PASSED"),
    ]

    cursor.executemany(
        """
        INSERT OR REPLACE INTO curated_dataplex_data_quality
        (dq_check_id, target_dataset, target_table, column_name, rule_type,
         rule_expression, evaluated_rows, passed_rows, pass_rate_pct, dq_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        dq_checks,
    )

    conn.commit()
    return {
        "llm_drivers_profiled": len(drivers_catalog),
        "llm_customers_profiled": len(customers_catalog),
        "llm_reviews_analyzed": len(reviews_data),
        "bqml_zone_predictions": len(bqml_predictions),
        "dataplex_dq_rules_passed": len(dq_checks),
    }


def execute_analytical_demos(conn: sqlite3.Connection) -> Dict[str, Any]:
    """Ejecuta las consultas analíticas y de gobernanza clave del Golden Demo usando consultas parametrizadas."""
    cursor = conn.cursor()

    # 1. Simulación de Row-Level Security (RLS): Filtrar solo por Borough = 'Manhattan'
    target_borough = "Manhattan"
    cursor.execute(
        """
        SELECT COUNT(*), GROUP_CONCAT(zone, ', ')
        FROM raw_biglake_rideshare_zone
        WHERE borough = ?
        """,
        (target_borough,),
    )
    rls_count, rls_zones = cursor.fetchone()

    # 2. Consulta Multi-Cloud Omni (AWS S3 vs Azure ADLS)
    cursor.execute(
        """
        SELECT cloud_provider,
               COUNT(*) AS total_rides,
               ROUND(AVG(passenger_count), 2) AS avg_passengers,
               ROUND(AVG(tip_amount), 2) AS avg_tip,
               ROUND(AVG(total_amount), 2) AS avg_total_fare
        FROM raw_aws_omni_s3_rides
        WHERE year = ? AND month = ?
        GROUP BY cloud_provider
        """,
        (2026, 11),
    )
    omni_summary = [
        {
            "cloud_provider": row[0],
            "total_rides": row[1],
            "avg_passengers": row[2],
            "avg_tip": row[3],
            "avg_total_fare": row[4],
        }
        for row in cursor.fetchall()
    ]

    # 3. BigSearch Index Lookup (Búsqueda instantánea sobre tarjeta enmascarada)
    target_masked_cc = "****-****-****-5710"
    cursor.execute(
        """
        SELECT rideshare_trip_id, pickup_location_id, dropoff_location_id,
               total_amount, credit_card_masked, credit_card_aead_cipher
        FROM enriched_iceberg_rideshare_trip
        WHERE credit_card_masked = ?
        """,
        (target_masked_cc,),
    )
    search_hits = [
        {
            "rideshare_trip_id": r[0],
            "pickup_location_id": r[1],
            "dropoff_location_id": r[2],
            "total_amount": r[3],
            "credit_card_masked": r[4],
            "credit_card_aead_cipher": r[5],
            "search_index_mode": "FULLY_USED (NO_OP_ANALYZER)",
        }
        for r in cursor.fetchall()
    ]

    # 4. Perfiles de Clientes + Emparejamiento Semántico con Conductores (Gemini + Embeddings)
    cursor.execute(
        """
        SELECT customer_id, customer_name, customer_attribute_summary,
               customer_review_summary, total_trip_count, avg_tip_amount,
               sum_total_amount, preferred_drivers_json
        FROM curated_llm_customer
        ORDER BY customer_id
        """
    )
    llm_profiles = [
        {
            "customer_id": r[0],
            "customer_name": r[1],
            "customer_attribute_summary": r[2],
            "customer_review_summary": r[3],
            "total_trip_count": r[4],
            "avg_tip_amount": r[5],
            "sum_total_amount": r[6],
            "preferred_drivers": json.loads(r[7]),
        }
        for r in cursor.fetchall()
    ]

    # 5. Predicciones BQML de Viajes de Alto Valor
    cursor.execute(
        """
        SELECT location_id, borough, zone, pickup_hour, ride_distance,
               is_raining, people_traveling_cnt, is_high_value_ride,
               predicted_probability, recommended_action
        FROM curated_bqml_predict_high_value_rides
        ORDER BY predicted_probability DESC
        """
    )
    bqml_results = [
        {
            "location_id": r[0],
            "borough": r[1],
            "zone": r[2],
            "pickup_hour": r[3],
            "ride_distance": r[4],
            "is_raining": bool(r[5]),
            "people_traveling_cnt": r[6],
            "is_high_value_ride": bool(r[7]),
            "predicted_probability": r[8],
            "recommended_action": r[9],
        }
        for r in cursor.fetchall()
    ]

    # 6. Vision AI Object Detection
    cursor.execute(
        """
        SELECT uri, location_id, detected_object, object_confidence,
               detected_landmark, landmark_confidence, safety_status
        FROM enriched_vision_ai_images_score
        ORDER BY object_confidence DESC
        """
    )
    vision_results = [
        {
            "uri": r[0],
            "location_id": r[1],
            "detected_object": r[2],
            "object_confidence": r[3],
            "detected_landmark": r[4],
            "landmark_confidence": r[5],
            "safety_status": r[6],
        }
        for r in cursor.fetchall()
    ]

    # 7. Dataplex Data Quality Report
    cursor.execute(
        """
        SELECT dq_check_id, target_dataset, target_table, column_name,
               rule_type, evaluated_rows, passed_rows, pass_rate_pct, dq_status
        FROM curated_dataplex_data_quality
        ORDER BY dq_check_id
        """
    )
    dataplex_results = [
        {
            "dq_check_id": r[0],
            "target_dataset": r[1],
            "target_table": r[2],
            "column_name": r[3],
            "rule_type": r[4],
            "evaluated_rows": r[5],
            "passed_rows": r[6],
            "pass_rate_pct": r[7],
            "dq_status": r[8],
        }
        for r in cursor.fetchall()
    ]

    return {
        "rls_governance_demo": {
            "policy_name": "rls_biglake_rideshare_zone_csv",
            "filter_expression": "borough = 'Manhattan'",
            "total_zones_before_rls": 20,
            "visible_zones_after_rls": rls_count,
            "manhattan_zones_sample": rls_zones,
        },
        "omni_multicloud_federation": omni_summary,
        "bigsearch_exact_lookup": search_hits,
        "gemini_llm_customer_profiles": llm_profiles,
        "bqml_high_value_predictions": bqml_results,
        "vision_ai_unstructured_analytics": vision_results,
        "dataplex_governance_quality": dataplex_results,
    }


def main() -> None:
    init_directories()
    if DB_PATH.exists():
        DB_PATH.unlink()

    conn = sqlite3.connect(str(DB_PATH))
    try:
        create_schema(conn)
        raw_stats = populate_raw_zone(conn)
        enriched_stats = populate_enriched_zone(conn)
        curated_stats = populate_curated_zone(conn)
        demo_outputs = execute_analytical_demos(conn)

        full_report = {
            "simulation_metadata": {
                "project_name": "Google Cloud Data Analytics Golden Demo - End-to-End Simulator",
                "execution_timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "architecture_level": "Level 200 / Level 300 Enterprise Lakehouse",
                "database_engine": f"SQLite Local Lakehouse ({DB_PATH.name})",
                "security_controls": [
                    "Parameterized SQL Queries (?)",
                    "PII Credit Card Masking (****-****-****-XXXX)",
                    "AEAD Column-Level Encryption & Crypto-Shredding",
                    "BigLake Row-Level Security (RLS) Policy Simulation",
                ],
            },
            "ingestion_metrics": {
                "raw_zone": raw_stats,
                "enriched_zone": enriched_stats,
                "curated_zone": curated_stats,
            },
            "analytical_walkthrough_results": demo_outputs,
        }

        with open(REPORT_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(full_report, f, indent=2, ensure_ascii=False)

        with open(DATA_DIR / "03_curated_zone" / "curated_summary_metrics.json", "w", encoding="utf-8") as f:
            json.dump(demo_outputs, f, indent=2, ensure_ascii=False)

        print("================================================================================")
        print("  GOOGLE CLOUD DATA ANALYTICS GOLDEN DEMO - SIMULACIÓN END-TO-END COMPLETADA")
        print("================================================================================")
        print(f"Base de Datos Lakehouse : {DB_PATH}")
        print(f"Reporte JSON Completo   : {REPORT_JSON_PATH}")
        print(f"1. RAW ZONE             : {raw_stats}")
        print(f"2. ENRICHED ZONE        : {enriched_stats}")
        print(f"3. CURATED ZONE         : {curated_stats}")
        print(f"4. RLS Policy Demo      : 20 zonas totales -> {demo_outputs['rls_governance_demo']['visible_zones_after_rls']} zonas visibles en Manhattan")
        print(f"5. BigSearch Lookup     : {len(demo_outputs['bigsearch_exact_lookup'])} coincidencia exacta indexada con PII enmascarado")
        print(f"6. Gemini 2.5 + Vector  : {len(demo_outputs['gemini_llm_customer_profiles'])} perfiles 360° con emparejamiento coseno")
        print(f"7. Dataplex DQ Status   : 100% reglas aprobadas ({curated_stats['dataplex_dq_rules_passed']}/5 checks)")
        print("================================================================================")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
