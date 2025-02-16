# Kubernetes Data Application Deployment

This project sets up a Kubernetes cluster using Kind (Kubernetes IN Docker) and deploys a data application with MySQL master-slave replication, a **Writer API**, and a **Reader API**. Additionally, it includes **Prometheus** and **Grafana** for monitoring.

---

## Prerequisites

- **Docker** installed
- **Kind** installed
- **Helm** installed (for deploying Prometheus and Grafana)
- **kubectl** installed

---

## Project Structure
```
my-k8s-data-app/
├── deployment/ # Kubernetes manifests
│ ├── mysql-secret.yaml # MySQL credentials secret
│ ├── mysql-master.yaml # MySQL master deployment
│ ├── mysql-master-service.yaml # MySQL master service
│ ├── mysql-slave.yaml # MySQL slave deployment
│ ├── mysql-slave-service.yaml # MySQL slave service
│ ├── writer-deployment.yaml # Writer deployment
│ ├── writer-service.yaml # Writer service (NodePort)
│ ├── reader-deployment.yaml # Reader deployment
│ └── reader-service.yaml # Reader service (NodePort)
├── writer/ # Writer application files
│ ├── requirements.txt # Python dependencies
│ ├── Dockerfile # Dockerfile for Writer
│ └── writer.py # Writer application code
└── reader/ # Reader application files
├── requirements.txt # Python dependencies
├── Dockerfile # Dockerfile for Reader
└── reader.py # Reader application code
```


---

## Deployment Steps

1. **Create Kind Cluster**:
   - The script creates a Kind cluster with NodePort mappings for:
     - **Grafana**: `3000`
     - **Prometheus**: `9090`
     - **Writer API**: `8080`
     - **Reader API**: `31081`

2. **Generate Kubernetes Manifests**:
   - MySQL master-slave replication setup.
   - Writer and Reader application deployments and services.

3. **Build and Load Docker Images**:
   - The Writer and Reader applications are built into Docker images and loaded into the Kind cluster.

4. **Deploy Prometheus and Grafana**:
   - Prometheus and Grafana are deployed using Helm with NodePort services for external access.

5. **Apply Kubernetes Manifests**:
   - All Kubernetes manifests are applied to deploy the MySQL master-slave, Writer, and Reader applications.

---

## Accessing Services

- **Grafana**: Accessible at `http://<host-ip>:3000`  
  - Default credentials: `admin/prom-operator`
- **Prometheus**: Accessible at `http://<host-ip>:9090`
- **Writer API**: Accessible at `http://<host-ip>:8080`
- **Reader API**: Accessible at `http://<host-ip>:31081`

---

## Application Details

### Writer Application

- **Function**: Writes data to the MySQL master database.
- **Features**:
  - Manual data entry via a web interface.
  - Exposes Prometheus metrics for write response time.
- **Endpoint**: Externally accessible via NodePort `8080`.

### Reader Application

- **Function**: Reads data from the MySQL master database.
- **Features**:
  - Displays database records in a web interface.
  - Exposes Prometheus metrics for read response time and row count.
- **Endpoint**: Externally accessible via NodePort `31081`.

### MySQL Replication

- **Master**: Handles write operations.
- **Slave**: Handles read operations (not used in this setup as Reader connects to the master for simplicity).

---

## Monitoring

- **Prometheus**: Scrapes metrics from the Writer and Reader applications.
- **Grafana**: Pre-configured to visualize the metrics collected by Prometheus.

---

## Creation Step 
To Create all the above Arch we can just run 

```bash
bash setup.sh
```

This will create all the Arch and make every thing Live 

---

## Cleanup

To delete the Kind cluster and clean up resources, run:

```bash
kind delete cluster --name mycluster
```

## Notes
Ensure Docker is running before executing the script.

The script assumes Helm is installed and configured to deploy Prometheus and Grafana.

The Writer and Reader images are built locally and loaded into the Kind cluster. If you want to push them to a remote registry, modify the Dockerfile and deployment manifests accordingly.

## Troubleshooting
If the Writer or Reader applications fail to start, check the logs using:
```
bash
kubectl logs <pod-name>
```
Ensure the MySQL master and slave pods are running before the Writer and Reader applications start.

If Prometheus or Grafana fails to deploy, ensure Helm is correctly installed and the repositories are added.

This README provides an overview of the deployment process and how to access the services. For detailed steps, refer to the script and Kubernetes manifests in the my-k8s-data-app directory.
