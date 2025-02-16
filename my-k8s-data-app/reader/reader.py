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
