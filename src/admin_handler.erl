%% Feel free to use, reuse and abuse the code in this file.

-module(admin_handler).

-export([init/3, handle/2, terminate/3]).

-export([start_port/3]).

init(_Transport, Req, Opts) ->
	{ok, Req, Opts}.

	%%will do wxith negative brokers for test & checker later

handle(Req, State) ->
	{{IP,_}, _} = cowboy_req:peer(Req),
	case IP of
		{127,0,0,1} ->
			{Url, _} = cowboy_req:path_info(Req),
			case Url of
				[<<"MT4">>, <<"add">>|Tail] -> %try to add a account to a pusher (mode 0)
					[Broker,User] = fill2(lists:map(fun to_int/1, Tail)),
					M = case ets:match_object(providers, {'_', 0, Broker}) of
						[{Pid,_,_}] -> Pid ! {send, <<12, Broker:32/little, User:32/little>>}, <<"k!">>;
						_ -> [<<"MT4 for ">>, Broker, <<" not started, start it first!">>]
					end,
					{ok, Req2} = cowboy_req:reply(200, [{<<"content-type">>, <<"text/html">>}],
						[<<"<p>">>, M, <<"  <a href='/#admin'>back</a></p>">>], Req);
				[<<"MT4">>, <<"start">>|Tail] ->
					[Mode,Broker] = fill2(lists:map(fun to_int/1, Tail)),
					M = case ets:match_object(providers, {'_', Mode, Broker}) of
						[] -> spawn(?MODULE, start_port, [Mode,Broker,State]), <<"k!">>;
						_ -> <<"already started">>
					end,
					{ok, Req2} = cowboy_req:reply(200, [{<<"content-type">>, <<"text/html">>}],
						[<<"<p>">>, M, <<"  <a href='/#admin'>back</a></p>">>], Req);
				[<<"MT4">>, <<"stop">>|Tail] ->
					[Mode,Broker] = fill2(lists:map(fun to_int/1, Tail)),
					Matches = ets:match_object(providers, {'_', Mode, Broker}),
					lists:foreach(fun({Pid,_,_}) -> Pid ! stop, ets:delete(providers, Pid) end, Matches),
					{ok, Req2} = cowboy_req:reply(200, [{<<"content-type">>, <<"text/html">>}],
						<<"<p>done!  <a href='/#admin'>back</a></p>">>, Req);
				_ ->
					{ok, Req2} = cowboy_req:reply(200, [{<<"content-type">>, <<"text/html">>}],
						<<"<p><a href='/admin/MT4'>MT4</a></p>">>, Req)
			end;
		_ ->
			{ok, Req2} = cowboy_req:reply(200, [], <<"not authorized">>, Req)
	end,		
	{ok, Req2, State}.


terminate(_Reason, _Req, _State) ->
	ok.


start_port('_', '_', {ExePath, Db}) ->
	start_port(0, '_', {ExePath, Db}),
	start_port(2, '_', {ExePath, Db});

start_port(Mode, Broker, {ExePath, Db}) ->
	ToAdd = get_accs(Mode, Broker),
	lists:foreach(fun(Range) ->
		R = lists:reverse(Range),
		_Port = open_port({spawn_executable, ExePath},[{args, [Db, jsx:encode(R)]}]),
		io:format(" launched MT4 ~p ~n",[R])
	end, ToAdd).

get_accs(0, Broker) ->
	{Stmt, Placeholder} = get_stmt(Broker),
	emysql:prepare(my_stmt, Stmt),
	Results = emysql:execute(my_pool, my_stmt, Placeholder),
	{_, ToAdd} = lists:foldl(fun([B,User], {C,A}) ->
		case B==C of
			false ->
				{B, [[User,B,0]|A]};
			true ->
				{B, [[User|hd(A)]|tl(A)]}
		end
	end, {-1,[]}, element(4,Results)),
	ToAdd;
get_accs(Mode, _) ->
	[[Mode]].

get_stmt('_') ->
	{<<"SELECT broker_id, broker_user FROM account WHERE status=1 ORDER BY broker_id">>, []};
get_stmt(Broker) ->
	{<<"SELECT broker_id, broker_user FROM account WHERE status=1 AND broker_id=?">>, [Broker]}.

to_int(ValueBin) ->
	try binary_to_integer(ValueBin) catch _:_ -> 0 end.

fill2([]) ->
	['_','_'];
fill2([A]) ->
	[A,'_'];
fill2([A,B]) ->
	[A,B].



