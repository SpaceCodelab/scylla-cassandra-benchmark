#!/bin/bash

echo "========================================"
echo "Cassandra Benchmark Starting"
echo "========================================"

CASSANDRA_HOSTS="cassandra-1,cassandra-2,cassandra-3"
KEYSPACE="ycsb"
WORKLOAD="/opt/ycsb/workloads/workloadc"
RESULTS_DIR="/results/cassandra"

mkdir -p $RESULTS_DIR

echo "Waiting for Cassandra cluster (60s)..."
sleep 60

echo "Creating keyspace..."
until docker exec cassandra-1 cqlsh -e "
CREATE KEYSPACE IF NOT EXISTS ycsb 
WITH replication = {'class':'NetworkTopologyStrategy', 'dc1':3};
" 2>/dev/null; do
  echo "Waiting for Cassandra..."
  sleep 10
done

sleep 10

echo "========================================"
echo "Loading Data (10M records - ~15 min)"
echo "========================================"

/opt/ycsb/bin/ycsb load cassandra-cql \
  -p hosts=$CASSANDRA_HOSTS \
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
  -p hosts=$CASSANDRA_HOSTS \
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
    -p hosts=$CASSANDRA_HOSTS \
    -p port=9042 \
    -p cassandra.keyspace=$KEYSPACE \
    -P $WORKLOAD \
    -p operationcount=5000000 \
    -threads $THREADS \
    -s 2>&1 | tee $RESULTS_DIR/benchmark_${THREADS}threads.txt
  
  sleep 10
done

docker exec cassandra-1 nodetool tablestats $KEYSPACE > $RESULTS_DIR/tablestats.txt

echo "========================================"
echo "Cassandra Benchmark Complete!"
echo "========================================"
