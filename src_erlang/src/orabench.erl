-module(orabench).

%% API exports
-export([main/1, insert_partition/5, select_partition/4]).

-define(DPI_MAJOR_VERSION, 3).
-define(DPI_MINOR_VERSION, 0).

%%====================================================================
%% API functions
%%====================================================================

%% escript Entry point
main([ConfigFile]) ->
  process_flag(trap_exit, true),
  {ok, [Config]} = file:consult(ConfigFile),
  #{
    benchmark_trials := Trials,

    file_bulk_name := BulkFile,
    file_bulk_header := Header,
    file_bulk_delimiter := BulkDelimiter,
    benchmark_number_partitions := Partitions,

    file_result_delimiter := ResultDelim,
    file_result_header := ResultHeader,
    file_result_name := ResultFile,

    benchmark_id := BMId,
    benchmark_comment := BMComment,
    benchmark_host_name := BMHost,
    benchmark_number_cores := BMCores,
    benchmark_os := BMOs,
    benchmark_user_name := BMUser,
    benchmark_database := BMDB,
    benchmark_core_multiplier := BMCoreMul,
    connection_fetch_size := ConnFetchSz,
    benchmark_transaction_size := BMTransSz,
    file_bulk_length := FBulkLen,
    file_bulk_size := FBulkSz,
    benchmark_batch_size := BMBatchSz,
  
    sql_insert := SqlInsert,
    sql_select := SqlSelect
  } = Config,
  {ok, Fd} = file:open(BulkFile, [read, raw, binary, {read_ahead, 1024 * 1024}]),
  Rows = load_data(Fd, list_to_binary(Header), BulkDelimiter, Partitions, []),
  if length(Rows) /= FBulkSz ->
      io:format("First = ~pñLast = ~p~n", [hd(Rows), lists:last(Rows)]),
      error({loaded_rows, length(Rows), 'of', FBulkSz});
    true -> ok
  end,
  ok = file:close(Fd),
  io:format("[~p:~p] Start ~p~n", [?FUNCTION_NAME, ?LINE, ?MODULE]),
  #{
    startTime := StartTs,
    endTime := EndTs
  } = Results = run_trials(Trials, Rows, Config),
  ok = application:load(oranif),
  io:format("[~p:~p] End ~p~n", [?FUNCTION_NAME, ?LINE, ?MODULE]),
  {ok, OranifVsn} = application:get_key(oranif, vsn),
  BMDrv = lists:flatten(io_lib:format("oranif (Version ~s)",[OranifVsn])),
  BMMod = lists:flatten(
    io_lib:format(
      "~p (~s)",
      [?MODULE, string:trim(erlang:system_info(system_version), both, "\n")]
    )
  ),
  RowFmt = string:join(
    [
      BMId, BMComment, BMHost, integer_to_list(BMCores), BMOs, BMUser, BMDB,
      BMMod, BMDrv,
      "~p", %trial_no
      "~s", % sql
      integer_to_list(BMCoreMul), integer_to_list(ConnFetchSz),
      integer_to_list(BMTransSz), integer_to_list(FBulkLen),
      integer_to_list(FBulkSz), integer_to_list(BMBatchSz),
      "~p", % action
      "~s", % start day time (yyyy-mm-dd hh24:mi:ss.fffffffff)
      "~s", % end day time (yyyy-mm-dd hh24:mi:ss.fffffffff)
      "~p", % duration second
      "~p~n" % duration nano second
    ],
    ResultDelim
  ),
  case filelib:is_regular(ResultFile) of
    false -> ok = file:write_file(ResultFile, ResultHeader ++ "\n");
    _ -> ok
  end,
  {ok, RFd} = file:open(ResultFile, [append, binary]),
  DurationMicros = timer:now_diff(EndTs, StartTs),
  maps:map(
    fun(
      Trial,
      #{startTime := STs, endTime := ETs, insert := Insrts, select := Slcts}
    ) ->
      {InsSTs, InsETs, TotalInserted} = maps:fold(
        fun(_Pid, {ISTs, IETs, Inserted}, {IISTs, IIETs, Count}) ->
          {[ISTs | IISTs], [IETs | IIETs], Count + Inserted}
        end,
        {[], [], 0}, maps:without([startTime, endTime], Insrts)
      ),
      InsMaxET = lists:max(InsETs),
      InsMinST = lists:min(InsSTs),
      InsDur = timer:now_diff(InsMaxET, InsMinST),
      ok = io:format(
        RFd, RowFmt,
        [Trial, SqlInsert, 'query', ts_str(InsMinST), ts_str(InsMaxET),
        round(InsDur / 1000000), InsDur * 1000]
      ),
      {SelSTs, SelETs, TotalSelected} = maps:fold(
        fun(_Pid, {ISTs, IETs, Selected}, {IISTs, IIETs, Count}) ->
          {[ISTs | IISTs], [IETs | IIETs], Count + Selected}
        end,
        {[], [], 0}, maps:without([startTime, endTime], Slcts)
      ),
      SelMaxET = lists:max(SelETs),
      SelMinST = lists:min(SelSTs),
      SelDur = timer:now_diff(SelMaxET, SelMinST),
      ok = io:format(
        RFd, RowFmt,
        [Trial, SqlSelect, 'query', ts_str(SelMinST), ts_str(SelMaxET),
        round(SelDur / 1000000), SelDur * 1000]
      ),
      DMs = timer:now_diff(ETs, STs),
      ok = io:format(
        RFd, RowFmt,
        [Trial, "", trial, ts_str(STs), ts_str(ETs),
        round(DMs / 1000000), DMs * 1000]
      ),
      if TotalInserted /= TotalSelected orelse FBulkSz /= TotalInserted ->
        io:format(
          "Trial ~p, Inserted ~p, Selected ~p, Missed ~p, Total ~p~n",
          [
            Trial, TotalInserted, TotalSelected, TotalInserted - TotalSelected,
            FBulkSz
          ]
        );
      true -> ok end
    end,
    maps:without([startTime, endTime], Results)
  ),
    ok = io:format(
    RFd, RowFmt,
    [0, "", benchmark, ts_str(StartTs), ts_str(EndTs),
    round(DurationMicros / 1000000), DurationMicros * 1000]
  ),
  ok = file:close(RFd),
  halt(0).

%%====================================================================
%% Internal functions
%%====================================================================
ts_str({_, _, Micro} = Timestamp) ->
  {{Y, M , D}, {H, Mi, S}} = calendar:now_to_local_time(Timestamp),
  list_to_binary(
    io_lib:format(
      "~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B.~-9..0B",
      [Y,M,D,H,Mi,S,Micro])
  ).

run_trials(
  Trials, Rows,
  #{
    connection_host := Host,
    connection_port := Port,
    connection_service := Service,
    connection_user := UserStr,
    connection_password := PasswordStr
  } = Config
) ->
  ok = dpi:load_unsafe(),
  Ctx = dpi:context_create(?DPI_MAJOR_VERSION, ?DPI_MINOR_VERSION),
  run_trials(
    Trials, Rows, Ctx,
    Config#{
      connection_user => list_to_binary(UserStr),
      connection_password =>  list_to_binary(PasswordStr),
      connection_string => list_to_binary(
        io_lib:format("~s:~p/~s", [Host, Port, Service])
      )
    },
    #{startTime => os:timestamp()}
  ).
run_trials(0, _, Ctx, _, Stats) ->
  ok = dpi:context_destroy(Ctx),
  Stats#{endTime => os:timestamp()};
run_trials(
  Trial, Rows, Ctx,
  #{
    connection_string := ConnectString,
    connection_user := User,
    connection_password := Password,

    sql_create := Create,
    sql_drop := Drop
  } = Config,
  Stats
) ->
  io:format("[~p:~p:~p] Start trial no ~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, Trial]),
  StartTime = os:timestamp(),
  Conn = dpi:conn_create(Ctx, User, Password, ConnectString, #{}, #{}),
  CreateStmt = dpi:conn_prepareStmt(Conn, false, list_to_binary(Create), <<>>),
  DropStmt = dpi:conn_prepareStmt(Conn, false, list_to_binary(Drop), <<>>),
  case catch dpi:stmt_execute(CreateStmt, ['DPI_MODE_EXEC_COMMIT_ON_SUCCESS']) of
    0 -> ok;
    {'EXIT', {{error, _, _, #{code := 955}}, _}} ->
      case dpi:stmt_execute(DropStmt, ['DPI_MODE_EXEC_COMMIT_ON_SUCCESS']) of
        0 ->
          case dpi:stmt_execute(CreateStmt, ['DPI_MODE_EXEC_COMMIT_ON_SUCCESS']) of
            0 -> ok;
            Error -> error({?LINE, Error})
          end;
        Error -> error({?LINE, Error})
      end;
    Error -> error({?LINE, Error})
  end,
  ok = dpi:stmt_close(CreateStmt, <<>>),
  ok = dpi:stmt_close(DropStmt, <<>>),
  ok = dpi:conn_close(Conn, [], <<>>),
  InsertStat = run_insert(Ctx, Rows, Config),
  SelectStat = run_select(Ctx, Config),
  run_trials(
    Trial - 1, Rows, Ctx, Config,
    Stats#{Trial => #{
      startTime => StartTime,
      endTime => os:timestamp(),
      insert => InsertStat,
      select => SelectStat
    }}
  ).

run_select(Ctx, #{benchmark_number_partitions := Partitions} = Config) ->
  Master = self(),
  Threads = [
    spawn_link(
      ?MODULE, select_partition, [Partition, Ctx, Master, Config]
    ) || Partition <- lists:seq(0, Partitions - 1)
  ],
  thread_join(Threads).

select_partition(
  Partition, Ctx, Master,
  #{
    connection_string := ConnectString,
    connection_user := User,
    connection_password := Password,
    sql_select := Select,
    connection_fetch_size := FetchSize
  }
) ->
  Conn = dpi:conn_create(Ctx, User, Password, ConnectString, #{}, #{}),
  SelectSql = list_to_binary(
    io_lib:format("~s WHERE partition_key = ~p", [Select, Partition])
  ),
  SelectStmt = dpi:conn_prepareStmt(Conn, false, SelectSql, <<>>),
  2 = dpi:stmt_execute(SelectStmt, []),
  ok = dpi:stmt_setFetchArraySize(SelectStmt, FetchSize),
  Start = os:timestamp(),
  Selected = (fun Fetch(Count) ->
    case dpi:stmt_fetch(SelectStmt) of
      #{found := true} ->
        %#{data := Key} = dpi:stmt_getQueryValue(SelectStmt, 1),
        %#{data := Data} = dpi:stmt_getQueryValue(SelectStmt, 2),
        %true = byte_size(dpi:data_getBytes(Key)) > 0,
        %true = byte_size(dpi:data_getBytes(Data)) > 0,
        Fetch(Count+1);
      #{found := false} -> Count
    end
  end)(0),
  ok = dpi:stmt_close(SelectStmt, <<>>),
  ok = dpi:conn_close(Conn, [], <<>>),
  Master ! {result, self(), {Start, os:timestamp(), Selected}}.

run_insert(Ctx, Rows, #{benchmark_number_partitions := Partitions} = Config) ->
  Master = self(),
  Threads = [
    spawn_link(
      ?MODULE, insert_partition, [Partition, Rows, Ctx, Master, Config]
    ) || Partition <- lists:seq(0, Partitions - 1)
  ],
  thread_join(Threads).

insert_partition(
  Partition, Rows, Ctx, Master,
  #{
    connection_string := ConnectString,
    connection_user := User,
    connection_password := Password,
    sql_insert := Insert,

    benchmark_batch_size := NumItersExec,
    benchmark_transaction_size := NumItersCommit,
    file_bulk_length := Size
  }
) ->
  Conn = dpi:conn_create(Ctx, User, Password, ConnectString, #{}, #{}),
  #{var := KeyVar} = dpi:conn_newVar(
    Conn, 'DPI_ORACLE_TYPE_VARCHAR', 'DPI_NATIVE_TYPE_BYTES', NumItersExec,
    Size, false, false, null
  ),
  #{var := DataVar} = dpi:conn_newVar(
    Conn, 'DPI_ORACLE_TYPE_VARCHAR', 'DPI_NATIVE_TYPE_BYTES', NumItersExec,
    Size, false, false, null
  ),
  InsertStmt = dpi:conn_prepareStmt(Conn, false, list_to_binary(Insert), <<>>),
  ok = dpi:stmt_bindByName(InsertStmt, <<"key">>, KeyVar),
  ok = dpi:stmt_bindByName(InsertStmt, <<"data">>, DataVar),
  Start = os:timestamp(),
  {Inserted, {NIE, _}} = exec(
    Partition, Rows,
    fun(Key, Data, {NIE, NIC}) ->
      {NewNIE, NewNIC} =
        if NIE < NumItersExec ->
            ok = dpi:var_setFromBytes(KeyVar, NIE, Key),
            ok = dpi:var_setFromBytes(DataVar, NIE, Data),
            {NIE + 1, NIC + 1};
          true ->
            ok = dpi:stmt_executeMany(InsertStmt, [], NumItersExec),
            ok = dpi:var_setFromBytes(KeyVar, 0, Key),
            ok = dpi:var_setFromBytes(DataVar, 0, Data),
            {1, NIC + 1}
        end,
      if NewNIC < NumItersCommit ->
          {NewNIE, NewNIC};
        true -> 
          ok = dpi:conn_commit(Conn),
          {NewNIE, 0}
      end
    end,
    {0, 0}
  ),
  if NIE > 0 -> ok = dpi:stmt_executeMany(InsertStmt, [], NIE);
  true -> ok end,
  ok = dpi:conn_commit(Conn),
  ok = dpi:var_release(KeyVar),
  ok = dpi:var_release(DataVar),
  ok = dpi:stmt_close(InsertStmt, <<>>),
  ok = dpi:conn_close(Conn, [], <<>>),
  Master ! {result, self(), {Start, os:timestamp(), Inserted}}.

load_data(Fd, Header, BulkDelimiter, Partitions, Rows) ->
  case file:read_line(Fd) of
    eof -> lists:reverse(Rows);
    {ok, Line0} ->
      %io:format("Header = ~p\tLine = ~p~n", [Header, Line0]),
      case string:trim(Line0, both, "\r\n") of
        Header ->
          load_data(Fd, Header, BulkDelimiter, Partitions, Rows);
        Line ->
          [<<KeyByte1:8, KeyByte2:8, _/binary>> = Key, Data] = string:split(
            Line, BulkDelimiter, all
          ),
          Partition = (KeyByte1 * 256 + KeyByte2) rem Partitions,
          load_data(
            Fd, Header, BulkDelimiter, Partitions,
            [{Partition, Key, Data} | Rows]
          )
      end
  end.

exec(Partition, Rows, Fun, Acc) -> exec(Partition, Rows, Fun, Acc, 0).
exec(_Partition, [], _Fun, Acc, Count) -> {Count, Acc};
exec(Partition, [{Partition, Key, Data} | Rows], Fun, Acc, Count) ->
  NewAcc = Fun(Key, Data, Acc),
  exec(Partition, Rows, Fun, NewAcc, Count + 1);
exec(Partition, [_ | Rows], Fun, Acc, Count) ->
  exec(Partition, Rows, Fun, Acc, Count).

thread_join(Threads) -> thread_join(Threads, #{}).
thread_join([], Results) -> Results;
thread_join(Threads, Results) ->
  receive
    {result, Pid, Result} -> thread_join(Threads, Results#{Pid => Result});
    {'EXIT', Thread, _Reason} ->
      thread_join(Threads -- [Thread], Results)
  after
    5000 ->
      io:format("waiting ~p~n", [length(Threads)]),
      thread_join(Threads, Results)
  end.
