#!/bin/bash

exec &> >(tee -i run_bench.log)
sleep .1

# ------------------------------------------------------------------------------
#
# run_bench.sh: Oracle Benchmark.
#
# ------------------------------------------------------------------------------

export ORA_BENCH_BENCHMARK_COMMENT='first test'

if [ -z "$ORA_BENCH_JAVA_CLASSPATH" ]; then
    export ORA_BENCH_JAVA_CLASSPATH=".;priv/java_jar/*"
fi

export ORA_BENCH_CONNECTION_HOST=0.0.0.0
export ORA_BENCH_CONNECTION_PORT=1521

export ORA_BENCH_FILE_CONFIGURATION_NAME=priv/ora_bench.properties

export ORA_BENCH_PASSWORD_SYS=oracle

echo "================================================================================"
echo "Start $0"
echo "--------------------------------------------------------------------------------"
echo "ora_bench - Oracle benchmark."
echo "--------------------------------------------------------------------------------"
echo "BENCHMARK_COMMENT       : $ORA_BENCH_BENCHMARK_COMMENT"
echo "CONNECTION_HOST         : $ORA_BENCH_CONNECTION_HOST"
echo "CONNECTION_PORT         : $ORA_BENCH_CONNECTION_PORT"
echo "FILE_CONFIGURATION_NAME : $ORA_BENCH_FILE_CONFIGURATION_NAME"
echo "--------------------------------------------------------------------------------"
date +"DATE TIME          : %d.%m.%Y %H:%M:%S"
echo "================================================================================"

EXITCODE="0"

export ORA_BENCH_BENCHMARK_DATABASE=db_11_2_xe
export ORA_BENCH_CONNECTION_SERVICE=xe
{ /bin/bash run_bench_database.sh; }

export ORA_BENCH_BENCHMARK_DATABASE=db_12_1_ee
export ORA_BENCH_CONNECTION_SERVICE=orclpdb1
{ /bin/bash run_bench_database.sh; }

export ORA_BENCH_BENCHMARK_DATABASE=db_12_2_ee
export ORA_BENCH_CONNECTION_SERVICE=orclpdb1
{ /bin/bash run_bench_database.sh; }

export ORA_BENCH_BENCHMARK_DATABASE=db_18_3_ee
export ORA_BENCH_CONNECTION_SERVICE=orclpdb1
{ /bin/bash run_bench_database.sh; }

export ORA_BENCH_BENCHMARK_DATABASE=db_18_4_xe
export ORA_BENCH_CONNECTION_SERVICE=xe
{ /bin/bash run_bench_database.sh; }

export ORA_BENCH_BENCHMARK_DATABASE=db_19_3_ee
export ORA_BENCH_CONNECTION_SERVICE=orclpdb1
{ /bin/bash run_bench_database.sh; }

EXITCODE=$?

echo ""
echo "--------------------------------------------------------------------------------"
date +"DATE TIME          : %d.%m.%Y %H:%M:%S"
echo "--------------------------------------------------------------------------------"
echo "End   $0"
echo "================================================================================"

exit $EXITCODE
