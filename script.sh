#!/bin/bash
set -e

echo "========================================"
echo "Creating Kind cluster configuration with NodePort mappings..."
echo "========================================"

# Create Kind cluster configuration with NodePort mappings for Grafana, Prometheus, Writer API, and Reader API.
cat > kind-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000  # Grafana
    hostPort: 3000
  - containerPort: 30900  # Prometheus
    hostPort: 9090
  - containerPort: 30080  # Writer API
    hostPort: 8080
  - containerPort: 30100  # Reader API
    hostPort: 31081
EOF

echo "========================================"
echo "Creating Kind cluster..."
echo "========================================"
kind create cluster --name mycluster --config kind-config.yaml

echo "========================================"
echo "Creating project structure..."
echo "========================================"
mkdir -p my-k8s-data-app/{deployment,writer,reader}

##########################################
# MySQL Master & Slave Manifests
##########################################

echo "Creating MySQL manifests..."

# mysql-secret.yaml: MySQL credentials secret
cat > my-k8s-data-app/deployment/mysql-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
data:
  root-password: cm9vdDEyMw==  # "root123"
  user: dXNlcjEyMw==          # "user123"
  password: cGFzczEyMw==      # "pass123"
EOF

# mysql-master.yaml: MySQL master deployment (using args so the default entrypoint runs)
cat > my-k8s-data-app/deployment/mysql-master.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql-master
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql-master
  template:
    metadata:
      labels:
        app: mysql-master
    spec:
      containers:
      - name: mysql-master
        image: mysql:5.7
        args: ["--innodb_log_file_size=26214400"]
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: root-password
        - name: MYSQL_DATABASE
          value: testdb
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: user
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        ports:
        - containerPort: 3306
EOF

# mysql-master-service.yaml: Service for MySQL master
cat > my-k8s-data-app/deployment/mysql-master-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: mysql-master
spec:
  selector:
    app: mysql-master
  ports:
  - protocol: TCP
    port: 3306
    targetPort: 3306
  type: ClusterIP
EOF

# mysql-slave.yaml: MySQL slave deployment (using args so initialization runs)
cat > my-k8s-data-app/deployment/mysql-slave.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql-slave
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql-slave
  template:
    metadata:
      labels:
        app: mysql-slave
    spec:
      containers:
      - name: mysql-slave
        image: mysql:5.7
        args: ["--innodb_log_file_size=26214400"]
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: root-password
        - name: MYSQL_REPLICATION_MODE
          value: slave
        - name: MYSQL_MASTER_HOST
          value: mysql-master
        - name: MYSQL_DATABASE
          value: testdb
        ports:
        - containerPort: 3306
EOF

# mysql-slave-service.yaml: Service for MySQL slave
cat > my-k8s-data-app/deployment/mysql-slave-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: mysql-slave
spec:
  selector:
    app: mysql-slave
  ports:
  - protocol: TCP
    port: 3306
    targetPort: 3306
  type: ClusterIP
EOF

##########################################
# Writer Application (Exposed via NodePort)
##########################################

echo "Creating Writer application manifests..."

# writer-deployment.yaml: Writer deployment
cat > my-k8s-data-app/deployment/writer-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: writer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: writer
  template:
    metadata:
      labels:
        app: writer
    spec:
      containers:
      - name: writer
        image: myrepo/writer:latest
        imagePullPolicy: Never
        env:
        - name: MYSQL_HOST
          value: mysql-master
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: user
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        - name: MYSQL_DATABASE
          value: testdb
        ports:
        - containerPort: 5000
EOF

# writer-service.yaml: NodePort Service to expose Writer API externally
cat > my-k8s-data-app/deployment/writer-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: writer-service
spec:
  selector:
    app: writer
  ports:
  - protocol: TCP
    port: 5000
    targetPort: 5000
    nodePort: 30080
  type: NodePort
EOF

##########################################
# Reader Application (Exposed via NodePort)
##########################################

echo "Creating Reader application manifests..."

# reader-deployment.yaml: Reader deployment
cat > my-k8s-data-app/deployment/reader-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reader
spec:
  replicas: 2
  selector:
    matchLabels:
      app: reader
  template:
    metadata:
      labels:
        app: reader
    spec:
      containers:
      - name: reader
        image: myrepo/reader:latest
        imagePullPolicy: Never
        env:
        - name: MYSQL_HOST
          value: mysql-master  # Updated to connect to the master for testing
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: user
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        - name: MYSQL_DATABASE
          value: testdb
        ports:
        - containerPort: 5000
EOF

# reader-service.yaml: NodePort Service to expose Reader API externally
cat > my-k8s-data-app/deployment/reader-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: reader-service
spec:
  selector:
    app: reader
  ports:
  - protocol: TCP
    port: 5000
    targetPort: 5000
    nodePort: 30100
  type: NodePort
EOF

##########################################
# Writer Application Files
##########################################

echo "Creating Writer application files..."

# my-k8s-data-app/writer/requirements.txt
cat > my-k8s-data-app/writer/requirements.txt << 'EOF'
mysql-connector-python
prometheus_client
Flask
EOF

# my-k8s-data-app/writer/Dockerfile
cat > my-k8s-data-app/writer/Dockerfile << 'EOF'
FROM python:3.8-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY writer.py .
CMD ["python", "writer.py"]
EOF

# my-k8s-data-app/writer/writer.py
cat > my-k8s-data-app/writer/writer.py << 'EOF'
from flask import Flask, request, render_template_string, redirect, url_for, Response
import mysql.connector
import os
import logging
import time
from prometheus_client import start_http_server, Summary, generate_latest

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Prometheus metric to measure write response time
WRITE_TIME = Summary('mysql_write_time_seconds', 'Time spent writing to MySQL')

def get_connection():
    """Retry until a connection to MySQL is established."""
    while True:
        try:
            conn = mysql.connector.connect(
                user=os.environ.get('MYSQL_USER'),
                password=os.environ.get('MYSQL_PASSWORD'),
                host=os.environ.get('MYSQL_HOST'),
                database=os.environ.get('MYSQL_DATABASE')
            )
            if conn.is_connected():
                logging.info("Connected to MySQL")
                return conn
        except Exception as e:
            logging.error("Waiting for MySQL: " + str(e))
        time.sleep(5)

# HTML template for manual data entry
HTML_TEMPLATE = """
<!doctype html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Writer Service - Manual Data Entry</title>
</head>
<body>
    <h1>Writer Service</h1>
    <form method="POST" action="{{ url_for('update') }}">
        <label for="data">Enter Data:</label>
        <input type="text" id="data" name="data" required>
        <input type="submit" value="Submit">
    </form>
    <p>Visit <a href="/metrics">/metrics</a> for Prometheus metrics.</p>
</body>
</html>
"""

@app.route("/", methods=["GET"])
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route("/update", methods=["POST"])
def update():
    data = request.form.get("data")
    if not data:
        return "No data provided", 400
    conn = get_connection()
    cursor = conn.cursor()
    start_time = time.time()
    # Create the table if it doesn't exist and insert the manually provided data.
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS data_table (
            id INT AUTO_INCREMENT PRIMARY KEY,
            data VARCHAR(255),
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("INSERT INTO data_table (data) VALUES (%s)", (data,))
    conn.commit()
    elapsed = time.time() - start_time
    WRITE_TIME.observe(elapsed)
    logging.info(f"Inserted record '{data}'; response time: {elapsed * 1000:.2f} ms")
    cursor.close()
    conn.close()
    return redirect(url_for("index"))

@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype="text/plain")

if __name__ == "__main__":
    # Start Prometheus metrics endpoint on port 8000 in a separate thread.
    start_http_server(8000)
    # Run the Flask application on port 5000.
    app.run(host="0.0.0.0", port=5000)

EOF

##########################################
# Reader Application Files
##########################################

echo "Creating Reader application files..."

# my-k8s-data-app/reader/requirements.txt
cat > my-k8s-data-app/reader/requirements.txt << 'EOF'
Flask
mysql-connector-python
prometheus_client
EOF

# my-k8s-data-app/reader/Dockerfile
cat > my-k8s-data-app/reader/Dockerfile << 'EOF'
FROM python:3.8-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY reader.py .
CMD ["python", "reader.py"]
EOF

# my-k8s-data-app/reader/reader.py
cat > my-k8s-data-app/reader/reader.py << 'EOF'
import time
import logging
import mysql.connector
import os
from flask import Flask, render_template_string, jsonify
from prometheus_client import start_http_server, Summary, Gauge

app = Flask(__name__)
READ_TIME = Summary('mysql_read_time_seconds', 'Time spent reading from MySQL')
ROW_COUNT_GAUGE = Gauge('row_count', 'Number of rows in data_table')
pod_name = os.environ.get('POD_NAME', 'unknown')

HTML_TEMPLATE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Reader Application - Database Records</title>
  <style>
    table { border-collapse: collapse; width: 80%; margin: 20px auto; }
    th, td { border: 1px solid #ccc; padding: 8px; text-align: center; }
    th { background-color: #f4f4f4; }
    body { font-family: Arial, sans-serif; }
    h1 { text-align: center; }
    .refresh { display: block; width: 100px; margin: 20px auto; padding: 10px; text-align: center; background: #007BFF; color: #fff; text-decoration: none; border-radius: 5px; }
  </style>
</head>
<body>
  <h1>Database Records</h1>
  <table>
    <thead>
      <tr>
        <th>ID</th>
        <th>Data</th>
        <th>Created At</th>
      </tr>
    </thead>
    <tbody>
      {% for row in rows %}
      <tr>
        <td>{{ row.id }}</td>
        <td>{{ row.data }}</td>
        <td>{{ row.created_at }}</td>
      </tr>
      {% endfor %}
    </tbody>
  </table>
  <a class="refresh" href="{{ url_for('index') }}">Refresh</a>
</body>
</html>
"""

@app.route("/")
def index():
    try:
        conn = mysql.connector.connect(
            user=os.environ.get("MYSQL_USER"),
            password=os.environ.get("MYSQL_PASSWORD"),
            host=os.environ.get("MYSQL_HOST"),
            database=os.environ.get("MYSQL_DATABASE")
        )
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM data_table ORDER BY id DESC")
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        return render_template_string(HTML_TEMPLATE, rows=rows)
    except Exception as e:
        logging.error("Error in index: " + str(e))
        return jsonify({"error": str(e)}), 500

@app.route("/api/rows")
def api_rows():
    try:
        conn = mysql.connector.connect(
            user=os.environ.get("MYSQL_USER"),
            password=os.environ.get("MYSQL_PASSWORD"),
            host=os.environ.get("MYSQL_HOST"),
            database=os.environ.get("MYSQL_DATABASE")
        )
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM data_table ORDER BY id DESC")
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        return jsonify(rows)
    except Exception as e:
        logging.error("Error in api/rows: " + str(e))
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    # Start Prometheus metrics endpoint on port 8001
    start_http_server(8001)
    logging.basicConfig(level=logging.INFO)
    app.run(host="0.0.0.0", port=5000)
EOF

##########################################
# Deploy Prometheus & Grafana via Helm with NodePort
##########################################

echo "Deploying Prometheus and Grafana using Helm..."
if command -v helm &> /dev/null; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace \
    --set grafana.service.type=NodePort --set grafana.service.nodePort=30000 \
    --set prometheus.service.type=NodePort --set prometheus.service.nodePort=30900
else
    echo "Helm not found! Please install Helm and re-run this script."
    exit 1
fi

##########################################
# Build and Deploy Images
##########################################

echo "Building Writer Docker image..."
docker build -t myrepo/writer:latest my-k8s-data-app/writer
echo "Building Reader Docker image..."
docker build -t myrepo/reader:latest my-k8s-data-app/reader

echo "Loading images into Kind cluster..."
kind load docker-image myrepo/writer:latest --name mycluster
kind load docker-image myrepo/reader:latest --name mycluster

##########################################
# Apply All Kubernetes Manifests
##########################################

echo "Applying Kubernetes manifests..."
kubectl apply -f my-k8s-data-app/deployment/mysql-secret.yaml
kubectl apply -f my-k8s-data-app/deployment/mysql-master.yaml
kubectl apply -f my-k8s-data-app/deployment/mysql-master-service.yaml
kubectl apply -f my-k8s-data-app/deployment/mysql-slave.yaml
kubectl apply -f my-k8s-data-app/deployment/mysql-slave-service.yaml
kubectl apply -f my-k8s-data-app/deployment/writer-deployment.yaml
kubectl apply -f my-k8s-data-app/deployment/writer-service.yaml
kubectl apply -f my-k8s-data-app/deployment/reader-deployment.yaml
kubectl apply -f my-k8s-data-app/deployment/reader-service.yaml

echo "========================================"
echo "Deployment complete! Access services via:"
echo "Grafana: http://$(hostname -I | awk '{print $1}'):3000 (admin/prom-operator)"
echo "Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo "Writer API (external): http://$(hostname -I | awk '{print $1}'):8080"
echo "Reader API (external): http://$(hostname -I | awk '{print $1}'):31081"
echo "========================================"

