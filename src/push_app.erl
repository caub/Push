%% Feel free to use, reuse and abuse the code in this file.

%% @private
-module(push_app).
-behaviour(application).

%% API.
-export([start/2, stop/1]).

%% API.
start(_Type, _Args) ->

	[Usr,Pwd,Host,Port,Name|T] = init:get_plain_arguments(),
	emysql:add_pool(my_pool, 1, Usr, Pwd, Host, list_to_integer(Port), Name, utf8),

	ets:new(providers, [public, named_table]), % in admin_handler only
	ets:new(subscribers, [public, named_table, bag, {read_concurrency,true}, {write_concurrency,true}]),
	%ets:new(cache, [public, named_table]),
	ets:new(log, [public, named_table]), %debug orders

	ets:new(users, [public, named_table]), %temp for demo

	logger:start_link(),

	Db = list_to_binary(io_lib:format("server=~s;user=~s;pwd=~s;database=~s;port=~s;",[Host,Usr,Pwd,Name,Port])),
	MT4Path = case T of [One] -> One; _ -> {ok, Path} = file:get_cwd(), Path ++ "/../MT4/bin/Debug/MT4.exe" end,

	Dispatch = cowboy_router:compile([
		{'_', [
			{"/bullet/[...]", bullet_handler, [{handler, push_handler}]},
			{"/admin/[...]", admin_handler, {MT4Path, Db}},
			{"/static/[...]", cowboy_static, [
				{directory, {priv_dir, bullet, []}},
				{mimetypes, [{<<".js">>, [<<"application/javascript">>]}]}
			]},
			{'_', default_handler, []} % for demo
		]}
	]),
	{ok, _} = cowboy:start_http(http, 100, [{port, 8080}],
		[{env, [{dispatch, Dispatch}]}]),

	{ok, _} = ranch:start_listener(recv, 20,
		ranch_tcp, [{port, 5555}], recv_protocol, []),

	{ok, _} = ranch:start_listener(recv_ping, 10,
		ranch_tcp, [{port, 5556}], recv_ping_protocol, []),

	% start some remote mt4 services directly..
	%admin_handler:start_port('_', '_', {MT4Path, Db}),

	push_sup:start_link().

stop(_State) ->
	ok.