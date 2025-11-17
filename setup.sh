#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 Real-Time AI Data Pipeline                   ║"
echo "║          Kafka • Debezium • Flink • Airflow • ClickHouse     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed. Please install Docker first.${NC}"
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ Docker Compose is not installed. Please install Docker Compose.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker and Docker Compose are installed${NC}"

# Create necessary directories
echo -e "${YELLOW}📁 Creating necessary directories...${NC}"
mkdir -p src/database/init-scripts
mkdir -p config/clickhouse
mkdir -p src/airflow-dags
mkdir -p src/flink-jobs

# Create sample database initialization script
echo -e "${YELLOW}📝 Creating sample database schema...${NC}"
cat > src/database/init-scripts/01-init.sql << 'EOF'
CREATE DATABASE ecommerce;

\c ecommerce;

-- Enable logical replication for Debezium
ALTER SYSTEM SET wal_level = logical;
SELECT pg_reload_conf();

CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200),
    price DECIMAL(10,2),
    category VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER,
    order_date TIMESTAMP DEFAULT NOW(),
    total_amount DECIMAL(10,2),
    status VARCHAR(50) DEFAULT 'pending'
);

CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER,
    product_id INTEGER,
    quantity INTEGER,
    price DECIMAL(10,2)
);

-- Insert sample data
INSERT INTO customers (name, email) VALUES 
('John Doe', 'john@example.com'),
('Jane Smith', 'jane@example.com'),
('Bob Johnson', 'bob@example.com');

INSERT INTO products (name, price, category) VALUES 
('Laptop', 999.99, 'Electronics'),
('Smartphone', 699.99, 'Electronics'),
('Headphones', 199.99, 'Electronics');

INSERT INTO orders (customer_id, total_amount) VALUES 
(1, 1199.98),
(2, 699.99);

INSERT INTO order_items (order_id, product_id, quantity, price) VALUES 
(1, 1, 1, 999.99),
(1, 3, 1, 199.99),
(2, 2, 1, 699.99);
EOF

# Create ClickHouse configuration
echo -e "${YELLOW}⚙️  Creating ClickHouse configuration...${NC}"
cat > config/clickhouse/storage.xml << 'EOF'
<yandex>
    <storage_configuration>
        <disks>
            <default>
                <path>/var/lib/clickhouse/</path>
            </default>
            <s3>
                <type>s3</type>
                <endpoint>http://minio:9000/data/</endpoint>
                <access_key_id>admin</access_key_id>
                <secret_access_key>password123</secret_access_key>
            </s3>
        </disks>
        <policies>
            <default>
                <volumes>
                    <default>
                        <disk>default</disk>
                    </default>
                    <s3>
                        <disk>s3</disk>
                    </s3>
                </volumes>
            </default>
        </policies>
    </storage_configuration>
</yandex>
EOF

# Create sample Airflow DAG
echo -e "${YELLOW}📊 Creating sample Airflow DAG...${NC}"
cat > src/airflow-dags/daily_pipeline.py << 'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python_operator import PythonOperator

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

def process_daily_data():
    print("Processing daily data pipeline...")
    # This would contain your actual data processing logic
    print("✅ Daily pipeline completed")

with DAG(
    'daily_data_pipeline',
    default_args=default_args,
    description='Daily data processing pipeline',
    schedule_interval=timedelta(days=1),
    catchup=False,
) as dag:

    process_task = PythonOperator(
        task_id='process_daily_data',
        python_callable=process_daily_data,
    )

    process_task
EOF

echo -e "${GREEN}✅ All configuration files created successfully!${NC}"

# Start the services
echo -e "${YELLOW}🚀 Starting services with Docker Compose...${NC}"
docker-compose up -d

echo -e "${YELLOW}⏳ Waiting for services to start...${NC}"
sleep 30

# Check if services are running
echo -e "${YELLOW}🔍 Checking service status...${NC}"

services=("zookeeper" "kafka" "connect" "postgres" "clickhouse" "airflow-webserver" "minio")

for service in "${services[@]}"; do
    if docker-compose ps | grep -q "$service.*Up"; then
        echo -e "${GREEN}✅ $service is running${NC}"
    else
        echo -e "${RED}❌ $service is not running${NC}"
    fi
done

# Create Debezium connector
echo -e "${YELLOW}🔗 Setting up Debezium PostgreSQL connector...${NC}"
sleep 10

curl -X POST -H "Content-Type: application/json" \
    --data '{
        "name": "postgres-connector",
        "config": {
            "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
            "database.hostname": "postgres",
            "database.port": "5432",
            "database.user": "postgres",
            "database.password": "password",
            "database.dbname": "ecommerce",
            "database.server.name": "postgres",
            "table.include.list": "public.*",
            "plugin.name": "pgoutput",
            "slot.name": "debezium",
            "publication.name": "dbz_publication"
        }
    }' \
    http://localhost:8083/connectors

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                     Setup Completed!                         ║"
echo "╚══════════════════════════════════════════════════════════════╗"
echo "📊 Access URLs:"
echo "   Airflow UI:    http://localhost:8080          (admin/admin)"
echo "   Kafka UI:      http://localhost:8082"
echo "   MinIO Console: http://localhost:9001          (admin/password123)"
echo "   ClickHouse:    http://localhost:8123"
echo ""
echo "🔧 Management Commands:"
echo "   View logs:     docker-compose logs [service]"
echo "   Stop:          docker-compose down"
echo "   Restart:       docker-compose restart"
echo "   Status:        docker-compose ps"
echo -e "${NC}"

# Display real-time logs option
echo -e "${YELLOW}📋 To view real-time logs, run: ${NC}docker-compose logs -f"
echo -e "${YELLOW}🛑 To stop all services, run: ${NC}docker-compose down"

# Test connection to key services
echo -e "${YELLOW}🧪 Testing connections...${NC}"

# Test ClickHouse
if curl -s http://localhost:8123/ping > /dev/null; then
    echo -e "${GREEN}✅ ClickHouse is responding${NC}"
else
    echo -e "${RED}❌ ClickHouse is not responding${NC}"
fi

# Test Airflow
if curl -s http://localhost:8080 > /dev/null; then
    echo -e "${GREEN}✅ Airflow is responding${NC}"
else
    echo -e "${RED}❌ Airflow is not responding${NC}"
fi

echo -e "${GREEN}🎉 Setup complete! Your real-time AI pipeline is ready.${NC}"
