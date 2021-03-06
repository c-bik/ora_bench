@echo off

rem ------------------------------------------------------------------------------
rem
rem run_bench_finalise.bat: Oracle Benchmark Run finalise.
rem
rem ------------------------------------------------------------------------------

if ["%ORA_BENCH_FILE_CONFIGURATION_NAME%"] EQU [""] (
    set ORA_BENCH_FILE_CONFIGURATION_NAME=priv/properties/ora_bench.properties
)
if ["%ORA_BENCH_JAVA_CLASSPATH%"] EQU [""] (
    set ORA_BENCH_JAVA_CLASSPATH=.;priv\java_jar\*
)

echo ================================================================================
echo Start %0
echo --------------------------------------------------------------------------------
echo ora_bench - Oracle benchmark - finalise benchmark run.
echo --------------------------------------------------------------------------------
echo FILE_CONFIGURATION_NAME : %ORA_BENCH_FILE_CONFIGURATION_NAME%
echo JAVA_CLASSPATH          : %ORA_BENCH_JAVA_CLASSPATH%
echo --------------------------------------------------------------------------------
echo:| TIME
echo ================================================================================

java -cp "%ORA_BENCH_JAVA_CLASSPATH%" ch.konnexions.orabench.OraBench finalise

echo --------------------------------------------------------------------------------
echo:| TIME
echo --------------------------------------------------------------------------------
echo End   %0
echo ================================================================================

exit /B %ERRORLEVEL%
