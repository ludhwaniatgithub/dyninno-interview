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

