%% Feel free to use, reuse and abuse the code in this file.

-module(logger).
-export([start_link/0, init/0]).

start_link() ->
	Pid = spawn_link(?MODULE, init, []),
	{ok, Pid}.

init() ->
	erlang:send_after(1000, self(), test),
	loop().

loop() ->
	receive
		test ->
			case ets:tab2list(log) of
				[] -> ok;
				D -> file:write_file("orders.log", io_lib:fwrite("~s:~n~p~n~n", [cowboy_clock:rfc1123(), D]), [append])
			end,
			ets:delete_all_objects(log),

			ets:insert(users, [
				{<<"gaelitier">>,<<"gwit.fx">>,0},
				{<<"john">>,<<"123">>,0}
			]),
			erlang:send_after(1000000, self(), test),
			loop()
	end.