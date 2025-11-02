#!/bin/bash

echo "========================================"
echo "ScyllaDB Benchmark Starting"
echo "========================================"

SCYLLA_HOSTS="scylla-1,scylla-2,scylla-3"
KEYSPACE="ycsb"
WORKLOAD="/opt/ycsb/workloads/workloadc"
RESULTS_DIR="/results/scylla"

mkdir -p $RESULTS_DIR

echo "Waiting for ScyllaDB cluster (60s)..."
sleep 60

echo "Creating keyspace..."
until docker exec scylla-1 cqlsh -e "
CREATE KEYSPACE IF NOT EXISTS ycsb 
WITH replication = {'class':'NetworkTopologyStrategy', 'replication_factor':3};
" 2>/dev/null; do
  echo "Waiting for ScyllaDB..."
  sleep 10
done

sleep 10

echo "========================================"
echo "Loading Data (10M records - ~15 min)"
echo "========================================"

/opt/ycsb/bin/ycsb load cassandra-cql \
  -p hosts=$SCYLLA_HOSTS \
  -p port=9042 \
  -p cassandra.keyspace=$KEYSPACE \
  -P $WORKLOAD \
  -threads 32 \
  -s 2>&1 | tee $RESULTS_DIR/load_output.txt

echo "Waiting for compaction (30s)..."
sleep 30

echo "========================================"
echo "Warm-up (1M ops)"
echo "========================================"

/opt/ycsb/bin/ycsb run cassandra-cql \
  -p hosts=$SCYLLA_HOSTS \
  -p port=9042 \
  -p cassandra.keyspace=$KEYSPACE \
  -P $WORKLOAD \
  -p operationcount=1000000 \
  -threads 32 \
  -s 2>&1 | tee $RESULTS_DIR/warmup_output.txt

sleep 10

for THREADS in 32 64 128; do
  echo "========================================"
  echo "Benchmark: $THREADS threads"
  echo "========================================"
  
  /opt/ycsb/bin/ycsb run cassandra-cql \
    -p hosts=$SCYLLA_HOSTS \
    -p port=9042 \
    -p cassandra.keyspace=$KEYSPACE \
    -P $WORKLOAD \
    -p operationcount=5000000 \
    -threads $THREADS \
    -s 2>&1 | tee $RESULTS_DIR/benchmark_${THREADS}threads.txt
  
  sleep 10
done

docker exec scylla-1 nodetool tablestats $KEYSPACE > $RESULTS_DIR/tablestats.txt

echo "========================================"
echo "ScyllaDB Benchmark Complete!"
echo "========================================"
